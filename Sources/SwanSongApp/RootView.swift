import AppKit
import SwanSongKit
import SwiftUI

enum LCDMotionLevel: CaseIterable, Hashable, Identifiable {
    case off
    case natural
    case strong

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .natural: "Natural"
        case .strong: "Strong"
        }
    }

    var responseScale: Double {
        switch self {
        case .off: 0
        case .natural: 1
        case .strong: 1.5
        }
    }

    static func nearest(to responseScale: Double) -> Self {
        allCases.min {
            abs($0.responseScale - responseScale)
                < abs($1.responseScale - responseScale)
        } ?? .natural
    }
}

enum PlayerControlCopy {
    static func firstRunHint(for hardwareModel: EngineHardwareModel) -> String {
        switch hardwareModel {
        case .pocketChallengeV2:
            "Arrows/WASD: Move · Z/X/C: Pass/Circle/Clear · Return: View · Esc/E: Escape"
        case .automatic, .wonderSwan, .wonderSwanColor, .swanCrystal:
            "X pad: Arrows · Y pad: WASD · B/A: Z/X · Start: Return"
        }
    }
}

enum StartupFileRowReadiness: Equatable {
    case ready
    case neededForLibrary
    case notInstalled

    var title: String {
        switch self {
        case .ready: "Ready"
        case .neededForLibrary: "Needed for library"
        case .notInstalled: "Not installed"
        }
    }

    var symbol: String {
        switch self {
        case .ready: "checkmark"
        case .neededForLibrary: "exclamationmark.circle.fill"
        case .notInstalled: "circle"
        }
    }
}

struct StartupFileLibraryReadiness: Equatable {
    let requiredKinds: Set<WonderSwanFirmwareKind>
    let installedKinds: Set<WonderSwanFirmwareKind>

    var missingRequiredKinds: Set<WonderSwanFirmwareKind> {
        requiredKinds.subtracting(installedKinds)
    }

    var summary: String {
        if requiredKinds.isEmpty {
            return installedKinds.isEmpty
                ? "Add files as needed"
                : "\(installedKinds.count) installed"
        }
        return missingRequiredKinds.isEmpty
            ? "Library systems ready"
            : "\(missingRequiredKinds.count) needed for library"
    }

    var summarySymbol: String {
        if requiredKinds.isEmpty { return "internaldrive" }
        return missingRequiredKinds.isEmpty
            ? "checkmark.circle.fill"
            : "exclamationmark.circle.fill"
    }

    var needsAttention: Bool {
        !missingRequiredKinds.isEmpty
    }

    var isReadyForLibrary: Bool {
        !requiredKinds.isEmpty && missingRequiredKinds.isEmpty
    }

    func rowReadiness(for kind: WonderSwanFirmwareKind) -> StartupFileRowReadiness {
        if installedKinds.contains(kind) { return .ready }
        return requiredKinds.contains(kind) ? .neededForLibrary : .notInstalled
    }
}

struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("automaticallyFitGameOrientation") private var automaticallyFitGameOrientation = true
    @AppStorage("libraryWindowHeight") private var libraryWindowHeight = 680.0
    @AppStorage("libraryWindowWidth") private var libraryWindowWidth = 1_040.0
    @AppStorage("pauseWhenInactive") private var pauseWhenInactive = true
    @AppStorage("showsSidebar") private var showsSidebar = true
    @Bindable var model: AppModel
    var translationLabOverviewGeometryProbe: TranslationLabOverviewGeometryProbe? = nil
    var gameConfidenceGeometryProbe: GameConfidenceGeometryProbe? = nil
    var usesDeterministicSidebarForOffscreenSnapshots = false
    @State private var appWindow: NSWindow?
    @State private var didOpenAutomatedSettings = false
    @State private var fullScreenTransitionInProgress = false
    @State private var lastFittedOrientation: PlayerWindowOrientation?
    @State private var libraryGeometryIsFrozen = false
    @State private var libraryWindowFrame: CGRect?
    @State private var pendingFitOrientation: PlayerWindowOrientation?
    @State private var pendingLibraryRestore = false

    var body: some View {
        ZStack {
            if model.isPlaying {
                PlayerView(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
            } else {
                LibraryShell(
                    model: model,
                    showsSidebar: $showsSidebar,
                    translationLabOverviewGeometryProbe: translationLabOverviewGeometryProbe,
                    gameConfidenceGeometryProbe: gameConfidenceGeometryProbe,
                    usesDeterministicSidebarForOffscreenSnapshots: usesDeterministicSidebarForOffscreenSnapshots
                )
                .transition(.opacity.combined(with: .scale(scale: 0.99)))
            }
        }
        .background {
            WindowAccessor(onWindowChange: captureWindow)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.isPlaying)
        .modifier(TranslationAccessibilityAnnouncements(model: model, window: appWindow))
        .onChange(of: model.isPlaying, initial: true) { _, isPlaying in
            handlePlayingStateChange(isPlaying)
        }
        .onChange(of: model.currentFrame?.isVertical) { _, isVertical in
            appDiagnostic("player orientation changed vertical=\(String(describing: isVertical)) autoFit=\(automaticallyFitGameOrientation)")
            guard model.isPlaying,
                  automaticallyFitGameOrientation,
                  let isVertical else { return }
            requestWindowFit(
                orientation: isVertical ? .vertical : .horizontal,
                force: false
            )
        }
        .onChange(of: model.fitWindowRequestID) { _, _ in
            guard model.isPlaying else { return }
            requestWindowFit(
                orientation: currentPlayerOrientation,
                force: true
            )
        }
        .onChange(of: automaticallyFitGameOrientation) { _, enabled in
            guard enabled, model.isPlaying else { return }
            requestWindowFit(
                orientation: currentPlayerOrientation,
                force: true
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) {
            notification in
            guard notification.object as? NSWindow === appWindow else { return }
            fullScreenTransitionInProgress = false
            resumeDeferredWindowChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) {
            notification in
            guard notification.object as? NSWindow === appWindow else { return }
            fullScreenTransitionInProgress = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) {
            notification in
            guard notification.object as? NSWindow === appWindow else { return }
            fullScreenTransitionInProgress = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) {
            notification in
            guard notification.object as? NSWindow === appWindow else { return }
            fullScreenTransitionInProgress = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) {
            notification in
            guard notification.object as? NSWindow === appWindow,
                  let appWindow else { return }
            if model.isPlaying {
                resumeDeferredWindowChange()
            } else {
                rememberLibraryFrame(appWindow.frame)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) {
            notification in
            updateLibraryWindowFrame(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) {
            notification in
            updateLibraryWindowFrame(from: notification)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.updateApplicationActivity(
                isActive: phase == .active,
                pauseWhenInactive: pauseWhenInactive
            )
        }
        .onChange(of: pauseWhenInactive) { _, shouldPause in
            model.updateApplicationActivity(
                isActive: scenePhase == .active || !shouldPause,
                pauseWhenInactive: shouldPause
            )
        }
        .onAppear {
            guard
                !didOpenAutomatedSettings,
                ProcessInfo.processInfo.environment["SWAN_SONG_OPEN_SETTINGS"] == "1"
            else { return }
            didOpenAutomatedSettings = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                openSettings()
            }
        }
        .alert(
            "SwanSong",
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { if !$0 { model.dismissPresentedError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                model.dismissPresentedError()
            }
        } message: {
            Text(model.presentedError ?? "")
        }
        .sheet(
            isPresented: Binding(
                get: { model.firmwareInstallationRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        model.cancelFirmwareInstallationRequest()
                    }
                }
            )
        ) {
            if let requiredFirmware = model.firmwareInstallationRequest {
                FirmwareRequirementView(model: model, kind: requiredFirmware)
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 10) {
                if let message = model.stateLoadUndoMessage {
                    NoticeBanner(
                        message: message,
                        symbol: "arrow.uturn.backward.circle.fill",
                        tint: SwanTheme.cyan,
                        actionTitle: "Undo",
                        onAction: model.undoLastStateLoad,
                        onDismiss: model.dismissStateLoadUndoNotice
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                }

                if let notice = model.presentedNotice {
                    NoticeBanner(message: notice) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                            model.presentedNotice = nil
                        }
                    }
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                }
            }
            .padding(16)
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: model.presentedNotice
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: model.stateLoadUndoMessage
        )
        .task(id: model.presentedNotice) {
            guard let notice = model.presentedNotice else { return }
            try? await Task.sleep(for: .seconds(7))
            guard model.presentedNotice == notice else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                model.presentedNotice = nil
            }
        }
        .task(id: model.stateLoadUndoMessage) {
            guard let message = model.stateLoadUndoMessage else { return }
            try? await Task.sleep(for: .seconds(10))
            guard model.stateLoadUndoMessage == message else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                model.dismissStateLoadUndoNotice()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in handleDrop(urls) }
    }

    private var currentPlayerOrientation: PlayerWindowOrientation {
        model.currentFrame?.isVertical == true ? .vertical : .horizontal
    }

    private func captureWindow(_ window: NSWindow?) {
        guard appWindow !== window else { return }
        appWindow = window
        guard let window else { return }
        appDiagnostic("captured main window frame=\(NSStringFromRect(window.frame)) playing=\(model.isPlaying)")
        if model.isPlaying {
            libraryGeometryIsFrozen = true
            if libraryWindowFrame == nil {
                libraryWindowFrame = rememberedLibraryFrame(around: window.frame)
            }
            if automaticallyFitGameOrientation,
               model.currentFrame != nil {
                requestWindowFit(
                    orientation: currentPlayerOrientation,
                    force: false
                )
            }
        } else {
            if !libraryGeometryIsFrozen {
                rememberLibraryFrame(window.frame)
            }
        }
    }

    private func handlePlayingStateChange(_ isPlaying: Bool) {
        guard let appWindow else { return }
        if isPlaying {
            libraryGeometryIsFrozen = true
            if libraryWindowFrame == nil {
                libraryWindowFrame = rememberedLibraryFrame(around: appWindow.frame)
            }
            lastFittedOrientation = nil
            pendingLibraryRestore = false
            if automaticallyFitGameOrientation,
               model.currentFrame != nil {
                requestWindowFit(
                    orientation: currentPlayerOrientation,
                    force: false
                )
            }
        } else {
            pendingFitOrientation = nil
            lastFittedOrientation = nil
            restoreLibraryWindow()
        }
    }

    private func requestWindowFit(
        orientation: PlayerWindowOrientation,
        force: Bool
    ) {
        guard let appWindow else { return }
        if !force, lastFittedOrientation == orientation { return }
        if fullScreenTransitionInProgress || appWindow.styleMask.contains(.fullScreen) {
            appDiagnostic("deferred \(orientation.rawValue) fit during fullscreen")
            pendingFitOrientation = orientation
            return
        }
        if appWindow.inLiveResize {
            appDiagnostic("suppressed \(orientation.rawValue) fit during live resize force=\(force)")
            if force { pendingFitOrientation = orientation }
            return
        }

        let visibleFrame = appWindow.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? appWindow.frame
        appWindow.minSize = PlayerWindowLayout.minimumSize(
            for: orientation,
            visibleFrame: visibleFrame
        )
        let target = PlayerWindowLayout.targetFrame(
            currentFrame: appWindow.frame,
            visibleFrame: visibleFrame,
            orientation: orientation
        )
        appDiagnostic("fitting window \(orientation.rawValue) from=\(NSStringFromRect(appWindow.frame)) to=\(NSStringFromRect(target))")
        appWindow.setFrame(target, display: true, animate: !reduceMotion)
        let appliedFrame = appWindow.frame
        appDiagnostic(
            "window layout applied surface=player orientation=\(orientation.rawValue) width=\(Int(appliedFrame.width)) height=\(Int(appliedFrame.height)) requestedWidth=\(Int(target.width)) requestedHeight=\(Int(target.height))"
        )
        lastFittedOrientation = orientation
        pendingFitOrientation = nil
    }

    private func restoreLibraryWindow() {
        guard let appWindow, let libraryWindowFrame else { return }
        if fullScreenTransitionInProgress
            || appWindow.styleMask.contains(.fullScreen)
            || appWindow.inLiveResize {
            pendingLibraryRestore = true
            return
        }
        let visibleFrame = appWindow.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? appWindow.frame
        appWindow.minSize = CGSize(width: 820, height: 560)
        let target = PlayerWindowLayout.restoredFrame(
            libraryFrame: libraryWindowFrame,
            currentFrame: appWindow.frame,
            visibleFrame: visibleFrame
        )
        appWindow.setFrame(target, display: true, animate: !reduceMotion)
        let appliedFrame = appWindow.frame
        appDiagnostic(
            "window layout applied surface=library width=\(Int(appliedFrame.width)) height=\(Int(appliedFrame.height)) requestedWidth=\(Int(target.width)) requestedHeight=\(Int(target.height))"
        )
        pendingLibraryRestore = false
        libraryGeometryIsFrozen = false
    }

    private func resumeDeferredWindowChange() {
        if pendingLibraryRestore, !model.isPlaying {
            restoreLibraryWindow()
        } else if let pendingFitOrientation, model.isPlaying {
            requestWindowFit(orientation: pendingFitOrientation, force: true)
        }
    }

    private func updateLibraryWindowFrame(from notification: Notification) {
        guard !model.isPlaying,
              !libraryGeometryIsFrozen,
              !fullScreenTransitionInProgress,
              let notificationWindow = notification.object as? NSWindow,
              notificationWindow === appWindow,
              !notificationWindow.styleMask.contains(.fullScreen) else { return }
        rememberLibraryFrame(notificationWindow.frame)
    }

    private func rememberLibraryFrame(_ frame: CGRect) {
        libraryWindowFrame = frame
        libraryWindowWidth = frame.width
        libraryWindowHeight = frame.height
    }

    private func rememberedLibraryFrame(around currentFrame: CGRect) -> CGRect {
        let size = CGSize(
            width: max(820, libraryWindowWidth),
            height: max(560, libraryWindowHeight)
        )
        return CGRect(
            x: currentFrame.midX - size.width / 2,
            y: currentFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        var gameFiles: [URL] = []
        var handled = false

        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                if let projects = try? TranslationProject.discover(at: url), !projects.isEmpty {
                    model.linkTranslationProject(at: url)
                } else {
                    model.importGames(in: url)
                }
                handled = true
            } else if url.lastPathComponent == "project.json" {
                model.linkTranslationProject(at: url)
                handled = true
            } else if GameImportPlanner.isSupportedGameFile(url) {
                gameFiles.append(url)
            }
        }

        if gameFiles.count == 1, let game = gameFiles.first {
            model.importGame(at: game)
            handled = true
        } else if !gameFiles.isEmpty {
            model.importGames(at: gameFiles)
            handled = true
        }
        return handled
    }
}

private struct TranslationAccessibilityAnnouncements: ViewModifier {
    @Bindable var model: AppModel
    let window: NSWindow?
    @State private var verificationIsActive = false
    @State private var lastAnnouncement: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: model.translationRouteRecordingIsPreparing) { wasPreparing, isPreparing in
                guard !wasPreparing, isPreparing else { return }
                announce("Preparing clean-boot route recording.")
            }
            .onChange(of: model.translationRouteIsRecording) { wasRecording, isRecording in
                guard !wasRecording, isRecording else { return }
                announce(
                    "Route recording started from Original at a clean boot.",
                    priority: .high
                )
            }
            .onChange(of: model.translationTestCaseNamingRequestID) { previousRequest, request in
                guard request != previousRequest else { return }
                let frame = model.latestTranslationRoute?.targetFrameNumber
                    ?? model.latestTranslationRoute?.totalFrames
                    ?? 0
                announce(
                    "Route saved at frame \(frame). Name the test case.",
                    priority: .high
                )
            }
            .onChange(of: model.translationComparisonPhase) { previousPhase, phase in
                if phase != nil {
                    verificationIsActive = true
                } else if previousPhase != nil {
                    Task { @MainActor in
                        await Task.yield()
                        verificationIsActive = false
                    }
                }
            }
            .onChange(of: model.presentedNotice) { _, notice in
                guard
                    let notice,
                    let announcement = announcement(forNotice: notice)
                else { return }
                announce(announcement, priority: .high)
            }
            .onChange(of: model.stateLoadUndoMessage) { _, message in
                guard message != nil else { return }
                announce(
                    "Saved state loaded. Undo is available.",
                    priority: .high
                )
            }
            .onChange(of: model.presentedError) { _, error in
                guard let error else { return }
                if verificationIsActive || isRouteVerificationError(error) {
                    announce(
                        "Route verification failed. Review the error alert for details.",
                        priority: .high
                    )
                }
            }
    }

    private func announcement(forNotice notice: String) -> String? {
        if notice.hasPrefix("Discarded the unfinished route draft")
            || notice.hasPrefix("Reset canceled the unfinished route draft") {
            return "Route recording canceled. No test case was saved."
        }
        if notice.hasPrefix("Route replay reached its recorded checkpoint") {
            let frame = model.currentFrame?.number
                ?? model.latestTranslationRoute?.targetFrameNumber
                ?? model.latestTranslationRoute?.totalFrames
                ?? 0
            return "Route replay reached its saved checkpoint at frame \(frame)."
        }
        if notice.hasPrefix("A/B route verification complete") {
            return "Verification complete. Original and Patched evidence are ready for review."
        }
        if notice.hasPrefix("Verified "), let count = model.latestTranslationSuiteRun?.cases.count {
            return "Route suite verification complete. \(count) test case\(count == 1 ? " is" : "s are") ready for review."
        }
        if notice.hasPrefix("Loaded state undone") {
            return "State load undone. Your previous game moment is restored."
        }
        return nil
    }

    private func isRouteVerificationError(_ error: String) -> Bool {
        let message = error.lowercased()
        return message.contains("cannot be verified")
            || message.contains("a/b route verification")
            || message.contains("a/b verification")
            || message.contains("route suite")
            || message.contains("verification suite")
            || message.contains("legacy route")
            || message.contains("recorded checkpoint")
    }

    private func announce(
        _ announcement: String,
        priority: NSAccessibilityPriorityLevel = .medium
    ) {
        guard lastAnnouncement != announcement else { return }
        lastAnnouncement = announcement
        NSAccessibility.post(
            element: window ?? NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: priority.rawValue,
            ]
        )
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard lastAnnouncement == announcement else { return }
            lastAnnouncement = nil
        }
    }
}

private struct NoticeBanner: View {
    let message: String
    let symbol: String
    let tint: Color
    let actionTitle: String?
    let onAction: (() -> Void)?
    let onDismiss: () -> Void

    init(
        message: String,
        symbol: String = "checkmark.circle.fill",
        tint: Color = .green,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.symbol = symbol
        self.tint = tint
        self.actionTitle = actionTitle
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 11) {
                noticeIcon
                noticeMessage
                    .frame(maxWidth: 340, alignment: .leading)
                noticeAction
                dismissButton
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    noticeIcon
                    noticeMessage
                    Spacer(minLength: 4)
                    dismissButton
                }
                if actionTitle != nil, onAction != nil {
                    noticeAction
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
        }
        .padding(.leading, 14)
        .padding(.trailing, 11)
        .padding(.vertical, 12)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.55))
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SwanSong notice: \(message)")
    }

    private var noticeIcon: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .font(.title3)
            .accessibilityHidden(true)
    }

    private var noticeMessage: some View {
        Text(message)
            .font(.callout)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var noticeAction: some View {
        if let actionTitle, let onAction {
            Button(actionTitle, action: onAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Dismiss")
        .accessibilityLabel("Dismiss notice")
    }
}

struct FirmwareRequirementView: View {
    static let accessibilityIdentifier = "firmware-required-sheet"
    static let minimumInteractiveDimension: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: AppModel
    let kind: WonderSwanFirmwareKind
    @State private var dropIsTargeted = false
    @AccessibilityFocusState private var errorHasAccessibilityFocus: Bool
    @FocusState private var primaryActionHasFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [SwanTheme.violet, SwanTheme.cyan.opacity(0.9)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Image(systemName: "power.circle.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(firmwareGateStatus.uppercased())
                                .font(.caption2.weight(.bold))
                                .tracking(0.8)
                                .foregroundStyle(
                                    model.firmwareInstallationIsReplacement
                                        ? Color.orange
                                        : SwanTheme.accent
                                )
                            Text(accessibilityContractHeadline)
                                .font(.title2.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text(requirementHeadline)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(firmwareRequirementIntroduction)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        requirementFact(
                            symbol: "gamecontroller.fill",
                            title: "Required system BIOS",
                            detail: systemUseDescription
                        )
                        Divider()
                        requirementFact(
                            symbol: "doc.zipper",
                            title: "Valid local file",
                            detail:
                                "\(kind.expectedByteCount / 1_024) KiB .rom or .bin, or a ZIP containing exactly one BIOS image."
                        )
                        Divider()
                        requirementFact(
                            symbol: "lock.shield.fill",
                            title: "Kept private",
                            detail:
                                "Checked on this Mac, then copied into SwanSong’s private Application Support folder."
                        )
                    }
                    .padding(15)
                    .background(
                        .background.secondary, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                    DisclosureGroup("Why SwanSong cannot provide this file") {
                        Text(
                            "The startup file is separate system software. SwanSong never bundles, searches for, downloads, uploads, or shares it. Your selected file is validated locally and remains on this Mac."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    }
                    .font(.callout.weight(.medium))

                    VStack(spacing: 10) {
                        Image(systemName: dropIsTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(dropIsTargeted ? SwanTheme.cyan : SwanTheme.accent)
                            .accessibilityHidden(true)

                        Text("Drop your \(kind.expectedByteCount / 1_024) KiB \(kind.title) BIOS here")
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        Text(".rom  ·  .bin  ·  ZIP with one BIOS image")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        Label("Checked, then copied to private local storage", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 132)
                    .background(
                        (dropIsTargeted ? SwanTheme.accent.opacity(0.13) : Color.primary.opacity(0.035)),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                dropIsTargeted ? SwanTheme.cyan.opacity(0.85) : Color.secondary.opacity(0.25),
                                style: StrokeStyle(lineWidth: dropIsTargeted ? 2 : 1, dash: [7, 6])
                            )
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        guard
                            !model.firmwareImportIsBusy,
                            let url = urls.first,
                            urls.count == 1
                        else { return false }
                        model.installRequestedFirmware(at: url, requiredKind: kind)
                        return true
                    } isTargeted: { targeted in
                        dropIsTargeted = targeted
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Drop the \(kind.title) BIOS here. Direct ROM, binary, or one-file ZIP."
                    )
                    .accessibilityIdentifier("firmware-required-drop-zone")

                    if let error = model.firmwareInstallationError {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("This BIOS can’t be used")
                                    .fontWeight(.semibold)
                                Text(error)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("BIOS error: \(error)")
                        .accessibilityIdentifier("firmware-required-error")
                        .accessibilityFocused($errorHasAccessibilityFocus)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .top).combined(with: .opacity)
                        )
                    }

                    if model.firmwareInstallationIsBusy {
                        HStack(spacing: 11) {
                            ProgressView()
                                .controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Checking BIOS…")
                                    .font(.callout.weight(.semibold))
                                Text("Identifying the system and creating the private local copy.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Checking and installing the \(kind.title) BIOS")
                    }

                }
                .padding(26)
            }

            Divider()
            firmwareActionBar
                .padding(.horizontal, 26)
                .padding(.vertical, 16)
                .background(.bar)
        }
        .frame(
            minWidth: 480,
            idealWidth: 620,
            maxWidth: 660,
            minHeight: 480,
            idealHeight: 650,
            maxHeight: 760
        )
        .accessibilityIdentifier(Self.accessibilityIdentifier)
        .interactiveDismissDisabled(model.firmwareInstallationIsBusy)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: model.firmwareInstallationError
        )
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                if let error = model.firmwareInstallationError {
                    postAccessibilityAnnouncement(
                        "BIOS error. \(error)",
                        priority: .high
                    )
                    errorHasAccessibilityFocus = true
                } else {
                    primaryActionHasFocus = true
                }
            }
        }
        .onChange(of: model.firmwareInstallationError) { _, error in
            guard let error else {
                errorHasAccessibilityFocus = false
                return
            }
            postAccessibilityAnnouncement(
                "BIOS error. \(error)",
                priority: .high
            )
            errorHasAccessibilityFocus = true
        }
        .onChange(of: model.firmwareInstallationIsBusy) { _, isBusy in
            guard isBusy else { return }
            postAccessibilityAnnouncement("Checking the \(kind.title) BIOS.")
        }
    }

    private var firmwareActionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                firmwareContinuationStatus
                Spacer(minLength: 12)
                firmwareActionButtons
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 12) {
                firmwareContinuationStatus
                firmwareActionButtons
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var firmwareContinuationStatus: some View {
        Label(
            model.firmwareInstallationIsReplacement
                ? "Different BIOS required to retry"
                : model.firmwareInstallationWillResumeLaunch
                ? "BIOS required before this action"
                : "BIOS required before play",
            systemImage: model.firmwareInstallationIsReplacement
                ? "arrow.clockwise.circle"
                : model.firmwareInstallationWillResumeLaunch
                ? "play.circle"
                : "lock.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(model.firmwareInstallationIsReplacement ? Color.orange : SwanTheme.accent)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var firmwareActionButtons: some View {
        HStack(spacing: 10) {
            Button("Not Now", role: .cancel) {
                model.cancelFirmwareInstallationRequest()
            }
            .keyboardShortcut(.cancelAction)
            .frame(minHeight: Self.minimumInteractiveDimension)
            .contentShape(Rectangle())
            .disabled(model.firmwareInstallationIsBusy)
            .accessibilityIdentifier("firmware-required-cancel")

            Button(accessibilityContractPrimaryActionTitle) {
                model.installRequestedFirmware(kind)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .frame(minHeight: Self.minimumInteractiveDimension)
            .contentShape(Rectangle())
            .focused($primaryActionHasFocus)
            .disabled(model.firmwareInstallationIsBusy)
            .accessibilityHint(primaryActionAccessibilityHint)
            .accessibilityIdentifier("firmware-required-choose")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var requirementHeadline: String {
        if model.firmwareInstallationIsReplacement {
            return "Choose a different local \(kind.title) BIOS. SwanSong will validate it privately and retry \(continuationDescription) automatically."
        }
        if let target = model.firmwareInstallationTargetTitle {
            return "\(target) is ready. Choose a local \(kind.expectedByteCount / 1_024) KiB BIOS and SwanSong will continue automatically."
        }
        return "Choose a local \(kind.expectedByteCount / 1_024) KiB BIOS before playing \(kind.title) games."
    }

    var accessibilityContractHeadline: String {
        model.firmwareInstallationIsReplacement
            ? "Different \(kind.title) BIOS Required"
            : "\(kind.title) BIOS Required"
    }

    var accessibilityContractPrimaryActionTitle: String {
        let title = model.firmwareInstallationPrimaryActionTitle.replacingOccurrences(
            of: "Startup File",
            with: "BIOS"
        )
        return title.hasSuffix("…") ? title : "\(title)…"
    }

    private var firmwareGateStatus: String {
        model.firmwareInstallationIsReplacement
            ? "Startup check needs attention"
            : "Required before play"
    }

    private var firmwareRequirementIntroduction: String {
        if model.firmwareInstallationIsReplacement {
            return "The emulator produced frames, but the current BIOS may not be the right dump for this game. A replacement must come from hardware you own or another source you are authorized to use."
        }
        return "This one-time system BIOS—also called a boot ROM or startup file—must come from hardware you own or another source you are authorized to use."
    }

    private var systemUseDescription: String {
        switch kind {
        case .monochrome:
            "The \(kind.expectedByteCount / 1_024) KiB BIOS starts original monochrome WonderSwan games."
        case .color:
            "The \(kind.expectedByteCount / 1_024) KiB BIOS starts WonderSwan Color and SwanCrystal games."
        case .pocketChallengeV2:
            "The \(kind.expectedByteCount / 1_024) KiB BIOS starts Pocket Challenge V2 software on its distinct Benesse hardware path."
        }
    }

    private var continuationDescription: String {
        model.firmwareInstallationTargetTitle.map { "\($0)" } ?? "the requested software"
    }

    private var primaryActionAccessibilityHint: String {
        if model.firmwareInstallationIsReplacement {
            return "Choose and validate another BIOS. SwanSong will retry \(continuationDescription) after replacement."
        }
        if model.firmwareInstallationWillResumeLaunch {
            return "Choose the required BIOS. SwanSong will continue \(continuationDescription) after setup."
        }
        return "Choose and validate the required BIOS for private local storage."
    }

    private func requirementFact(
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(SwanTheme.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StartupFileGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [SwanTheme.violet, SwanTheme.cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Image(systemName: "cpu.fill")
                                .font(.system(size: 31, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 68, height: 68)
                        .shadow(color: SwanTheme.violet.opacity(0.28), radius: 14, y: 7)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("About Startup Files")
                                .font(.title2.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text("A small system program—also called a boot ROM or BIOS—that runs before the game starts.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text("SwanSong needs the matching startup file to start games, but it isn’t part of SwanSong. You add it once; the app validates it locally and keeps a private copy in Application Support.")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            startupFileCard(
                                title: "WonderSwan",
                                size: "4 KiB",
                                detail: "Original monochrome games",
                                symbol: "circle.grid.cross"
                            )
                            startupFileCard(
                                title: "WonderSwan Color",
                                size: "8 KiB",
                                detail: "Color and SwanCrystal games",
                                symbol: "circle.hexagongrid.fill"
                            )
                        }
                        startupFileCard(
                            title: "Pocket Challenge V2",
                            size: "4 KiB",
                            detail: "Benesse keypad software",
                            symbol: "rectangle.grid.2x2.fill"
                        )
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("How setup works")
                            .font(.headline)
                        guideStep(
                            number: 1,
                            title: "Make an authorized local copy",
                            detail: "Use a file copied from hardware you own or another source you are authorized to use. Rules vary by location."
                        )
                        guideStep(
                            number: 2,
                            title: "Choose or drop the file",
                            detail: "SwanSong accepts .rom, .bin, or a ZIP containing exactly one startup file."
                        )
                        guideStep(
                            number: 3,
                            title: "SwanSong verifies it privately",
                            detail: "Size and structure checks happen on this Mac. The file is never uploaded."
                        )
                    }
                    .padding(18)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title3)
                            .foregroundStyle(SwanTheme.cyan)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Why there is no download button")
                                .font(.callout.weight(.semibold))
                            Text("Public availability does not grant redistribution permission. SwanSong does not bundle, search for, download, or upload startup files.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .background(SwanTheme.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(SwanTheme.violet.opacity(0.22), lineWidth: 1)
                    }
                }
                .padding(26)
            }

            Divider()

            HStack {
                Label("Local-only validation", systemImage: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .frame(width: 650, height: 650)
        .background(SwanTheme.libraryBackground)
    }

    private func startupFileCard(
        title: String,
        size: String,
        detail: String,
        symbol: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(SwanTheme.accent)
                .frame(width: 34, height: 34)
                .background(SwanTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text("\(size) · \(detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func guideStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(SwanTheme.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private func postAccessibilityAnnouncement(
    _ message: String,
    priority: NSAccessibilityPriorityLevel = .medium
) {
    NSAccessibility.post(
        element: NSApplication.shared,
        notification: .announcementRequested,
        userInfo: [
            .announcement: message,
            .priority: priority.rawValue,
        ]
    )
}

private struct LibraryShell: View {
    @Bindable var model: AppModel
    @Binding var showsSidebar: Bool
    var translationLabOverviewGeometryProbe: TranslationLabOverviewGeometryProbe? = nil
    var gameConfidenceGeometryProbe: GameConfidenceGeometryProbe? = nil
    var usesDeterministicSidebarForOffscreenSnapshots = false

    var body: some View {
        Group {
            if usesDeterministicSidebarForOffscreenSnapshots {
                HStack(spacing: 0) {
                    TranslationOverviewSnapshotSidebar(model: model)
                        .frame(width: 230)
                    Divider()
                    detail
                        .frame(minWidth: 590)
                }
            } else {
                NavigationSplitView(columnVisibility: splitVisibility) {
                    AppSidebar(model: model)
                        .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 260)
                } detail: {
                    detail
                        .frame(minWidth: 600)
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var splitVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { showsSidebar ? .all : .detailOnly },
            set: { showsSidebar = $0 != .detailOnly }
        )
    }

    private var detail: some View {
        NavigationStack {
            if model.section == .translationLab {
                TranslationLabView(
                    model: model,
                    overviewGeometryProbe: translationLabOverviewGeometryProbe
                )
            } else {
                LibraryView(
                    model: model,
                    gameConfidenceGeometryProbe: gameConfidenceGeometryProbe,
                    usesDeterministicSidebarForOffscreenSnapshots:
                        usesDeterministicSidebarForOffscreenSnapshots
                )
            }
        }
    }
}

private struct AppSidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SwanSongIcon(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SwanSong")
                        .font(.headline)
                    Text("WONDERSWAN")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.25)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            List(selection: $model.section) {
                Section("Browse") {
                    ForEach(AppModel.Section.allCases) { section in
                        Label(section.rawValue, systemImage: section.symbol)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(.bar)
        .accessibilityIdentifier("app-sidebar")
    }
}

private struct TranslationOverviewSnapshotSidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SwanSongIcon(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SwanSong")
                        .font(.headline)
                    Text("WONDERSWAN")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.25)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 5) {
                Text("BROWSE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)

                ForEach(AppModel.Section.allCases) { section in
                    Label(section.rawValue, systemImage: section.symbol)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .foregroundStyle(
                            section == model.section ? Color.accentColor : Color.primary
                        )
                        .background(
                            section == model.section
                                ? Color.accentColor.opacity(0.14)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("app-sidebar")
    }
}

private extension GameLibrarySortOrder {
    var symbol: String {
        switch self {
        case .title: "textformat"
        case .recentlyAdded: "plus.circle"
        case .recentlyPlayed: "clock"
        }
    }
}

private struct LibraryFirmwareRequirement: Identifiable {
    let kind: WonderSwanFirmwareKind
    let gameCount: Int

    var id: WonderSwanFirmwareKind { kind }
}

private struct LibraryFirmwareBanner: View {
    let requirements: [LibraryFirmwareRequirement]
    let onSetup: (WonderSwanFirmwareKind) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                bannerIdentity
                Spacer(minLength: 12)
                setupActions
            }

            VStack(alignment: .leading, spacing: 14) {
                bannerIdentity
                setupActions
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [SwanTheme.violet.opacity(0.14), SwanTheme.cyan.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SwanTheme.accent.opacity(0.24))
        }
        .accessibilityIdentifier("library-firmware-setup-banner")
    }

    private var bannerIdentity: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SwanTheme.violet, SwanTheme.cyan.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "cpu.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(requirements.count == 1 ? "System startup file required" : "System startup files required")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(requirementSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label("User supplied · checked locally · never downloaded", systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var setupActions: some View {
        HStack(spacing: 9) {
            ForEach(requirements) { requirement in
                Button {
                    onSetup(requirement.kind)
                } label: {
                    Label(
                        "Add \(requirement.kind.title)…",
                        systemImage: requirement.kind == .color
                            ? "circle.hexagongrid.fill"
                            : "circle.grid.cross"
                    )
                }
                .buttonStyle(.bordered)
                .tint(requirement.id == requirements.first?.id ? SwanTheme.accent : Color.gray)
                .help(
                    "Add the \(requirement.kind.expectedByteCount / 1_024) KiB \(requirement.kind.title) startup file"
                )
                .accessibilityIdentifier("library-add-\(requirement.kind.rawValue)-firmware")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var requirementSummary: String {
        requirements.map { requirement in
            "\(requirement.gameCount) \(requirement.kind.title) game\(requirement.gameCount == 1 ? "" : "s")"
        }
        .joined(separator: " and ")
        + " cannot start until the matching local file is added once."
    }
}

private struct LibraryView: View {
    @Bindable var model: AppModel
    var gameConfidenceGeometryProbe: GameConfidenceGeometryProbe? = nil
    var usesDeterministicSidebarForOffscreenSnapshots = false
    @AppStorage("librarySortOption") private var sortOptionRaw = GameLibrarySortOrder.title.rawValue
    @AppStorage("showsLibraryInspector") private var showsLibraryInspector = true
    @State private var searchText = ProcessInfo.processInfo.environment[
        "SWAN_SONG_LIBRARY_SEARCH"
    ] ?? ""

    private let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 18),
    ]

    var body: some View {
        Group {
            if usesDeterministicSidebarForOffscreenSnapshots,
               showsLibraryInspector,
               let game = selectedInspectorGame {
                HStack(spacing: 0) {
                    libraryContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    gameInspector(game)
                        .frame(width: 310)
                }
            } else {
                libraryContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(model.section.rawValue)
        .tint(SwanTheme.accent)
        .background(SwanTheme.libraryBackground.ignoresSafeArea())
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "Search \(model.section.rawValue)"
        )
        .toolbar { libraryToolbar }
        .inspector(isPresented: inspectorPresentation) {
            if let game = selectedInspectorGame {
                gameInspector(game)
            }
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if model.visibleGames.isEmpty {
            LibraryEmptyState(
                title: emptyTitle,
                description: emptyDescription,
                symbol: emptySymbol,
                showsOpenAction: model.section == .library,
                onOpen: model.chooseGame
            )
        } else if displayedGames.isEmpty {
            ContentUnavailableView {
                Label("No Games Found", systemImage: "magnifyingglass")
            } description: {
                Text("No games in \(model.section.rawValue) match “\(searchText)”.")
            } actions: {
                Button("Clear Search") {
                    searchText = ""
                }
            }
        } else {
            ScrollView {
                VStack(spacing: 18) {
                    if !firmwareRequirements.isEmpty {
                        LibraryFirmwareBanner(
                            requirements: firmwareRequirements,
                            onSetup: model.requestFirmwareSetup
                        )
                    }

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(displayedGames) { game in
                            gameCard(game)
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    private func gameCard(_ game: GameRecord) -> some View {
        GameCard(
            game: game,
            artwork: model.gameArtwork[game.id],
            confidence: model.gameConfidence(for: game),
            isSelected: model.selectedGameID == game.id,
            canPlay: model.canPlayGame(game),
            managedHealth: model.managedGameHealth[game.id],
            isCheckingManagedCopy: model.checkingManagedGameIDs.contains(game.id),
            isRepairingManagedCopy: model.repairingGameID == game.id,
            requiredFirmware: model.missingFirmware(for: game),
            onSelect: { model.selectedGameID = game.id },
            onPlay: { model.play(game.id) },
            onRepair: { model.repairManagedGame(game.id) },
            onReAdd: model.chooseGame,
            onInstallFirmware: { model.play(game.id) },
            onFavorite: { model.toggleFavorite(game.id) },
            onUseProceduralArtwork: { model.useProceduralArtwork(game.id) },
            onCaptureArtworkNextPlay: { model.captureArtworkNextTimePlayed(game.id) },
            canReveal: model.canRevealGame(game),
            onReveal: { model.revealGame(game.id) },
            onRemove: { model.remove(game.id) }
        )
    }

    private func gameInspector(_ game: GameRecord) -> some View {
        GameInspector(
            game: game,
            artwork: model.gameArtwork[game.id],
            confidence: model.gameConfidence(for: game),
            canPlay: model.canPlayGame(game),
            managedHealth: model.managedGameHealth[game.id],
            isCheckingManagedCopy: model.checkingManagedGameIDs.contains(game.id),
            isRepairingManagedCopy: model.repairingGameID == game.id,
            requiredFirmware: model.missingFirmware(for: game),
            canImportSave: model.canImportPocketSave,
            canExportSave: model.canExportPocketSave,
            onPlay: { model.play(game.id) },
            onRepair: { model.repairManagedGame(game.id) },
            onReAdd: model.chooseGame,
            onInstallFirmware: { model.play(game.id) },
            onImportSave: model.importPocketSave,
            onExportSave: model.exportPocketSave,
            onSetCompatibilityVerdict: {
                model.updateGameCompatibilityVerdict($0, for: game.id)
            },
            onSaveCompatibilityNote: {
                model.updateGameCompatibilityNote($0, for: game.id)
            },
            geometryProbe: gameConfidenceGeometryProbe
        )
        .id(game.id)
        .inspectorColumnWidth(min: 280, ideal: 310, max: 340)
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker("Sort By", selection: $sortOptionRaw) {
                    ForEach(GameLibrarySortOrder.allCases) { option in
                        Label(option.rawValue, systemImage: option.symbol)
                            .tag(option.rawValue)
                    }
                }
            } label: {
                Label("Sort Games", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort Games")
            .accessibilityLabel("Sort Games")
            .accessibilityValue(sortOption.rawValue)
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Open Game…", systemImage: "play", action: model.chooseGame)
                Divider()
                Button("Add Games to Library…", systemImage: "rectangle.stack.badge.plus", action: model.chooseGames)
                Button("Add Folder to Library…", systemImage: "folder.badge.plus") {
                    model.chooseGameFolder()
                }
            } label: {
                Label("Add Games", systemImage: "plus")
            }
            .help("Open or add supported games")
            .accessibilityLabel("Open or add supported games")
            .disabled(model.gameImportIsBusy)
        }

        if model.gameImportIsBusy {
            ToolbarItem {
                ProgressView()
                    .controlSize(.small)
                    .help("Importing and validating games")
                    .accessibilityLabel("Importing and validating games")
            }
        }

        ToolbarItem {
            Button {
                showsLibraryInspector.toggle()
            } label: {
                Label(
                    showsLibraryInspector ? "Hide Game Inspector" : "Show Game Inspector",
                    systemImage: "sidebar.trailing"
                )
            }
            .help(showsLibraryInspector ? "Hide Game Inspector" : "Show Game Inspector")
            .accessibilityLabel(
                showsLibraryInspector ? "Hide Game Inspector" : "Show Game Inspector"
            )
            .disabled(selectedInspectorGame == nil)
        }
    }

    private var inspectorPresentation: Binding<Bool> {
        Binding(
            get: {
                !usesDeterministicSidebarForOffscreenSnapshots
                    && showsLibraryInspector
                    && selectedInspectorGame != nil
            },
            set: { showsLibraryInspector = $0 }
        )
    }

    private var sortOption: GameLibrarySortOrder {
        GameLibrarySortOrder(rawValue: sortOptionRaw) ?? .title
    }

    private var displayedGames: [GameRecord] {
        GameLibraryQuery().games(
            in: model.games,
            filter: libraryFilter,
            matching: searchText,
            sortedBy: sortOption
        )
    }

    private var firmwareRequirements: [LibraryFirmwareRequirement] {
        guard model.section == .library else { return [] }
        return WonderSwanFirmwareKind.allCases.compactMap { kind in
            let gameCount = model.games.count { game in
                model.firmwareKind(for: game) == kind
                    && model.missingFirmware(for: game) == kind
            }
            guard gameCount > 0 else { return nil }
            return LibraryFirmwareRequirement(kind: kind, gameCount: gameCount)
        }
    }

    private var libraryFilter: GameLibraryFilter {
        switch model.section {
        case .library: .all
        case .favorites: .favorites
        case .recent: .recentlyPlayed
        case .translationLab: .all
        }
    }

    private var selectedInspectorGame: GameRecord? {
        guard let selectedGameID = model.selectedGameID else { return nil }
        return displayedGames.first { $0.id == selectedGameID }
    }

    private var emptyTitle: String {
        switch model.section {
        case .library: "Your WonderSwan library is empty"
        case .favorites: "No favorites yet"
        case .recent: "Nothing played recently"
        case .translationLab: "No translation project linked"
        }
    }

    private var emptySymbol: String {
        switch model.section {
        case .library: "rectangle.stack.badge.plus"
        case .favorites: "star"
        case .recent: "clock"
        case .translationLab: "character.book.closed"
        }
    }

    private var emptyDescription: String {
        switch model.section {
        case .library: "Open a .ws, .wsc, .pc2, .pcv2, or one-game ZIP. SwanSong keeps a private managed copy."
        case .favorites: "Mark the games you return to most often."
        case .recent: "Games appear here after they have been played."
        case .translationLab: "Link a private translation-toolkit project to begin."
        }
    }
}

private struct LibraryEmptyState: View {
    let title: String
    let description: String
    let symbol: String
    let showsOpenAction: Bool
    let onOpen: () -> Void

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [SwanTheme.violet.opacity(0.09), SwanTheme.cyan.opacity(0.025), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 260
            )
            .frame(width: 560, height: 460)
            .accessibilityHidden(true)

            VStack(spacing: 16) {
                if showsOpenAction {
                    SwanSongIcon(size: 86)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 40, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 86, height: 86)
                        .background(.quaternary.opacity(0.55), in: Circle())
                        .accessibilityHidden(true)
                }

                VStack(spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 430)
                }

                if showsOpenAction {
                    Button("Open a Game…", systemImage: "plus", action: onOpen)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                    HStack(spacing: 8) {
                        formatPill(".ws")
                        formatPill(".wsc")
                        formatPill(".pc2 / .pcv2")
                        formatPill("one-game ZIP")
                        Label("or drag and drop", systemImage: "arrow.down.to.line.compact")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func formatPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced().weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

private enum EvidenceComparisonMode: String, CaseIterable, Identifiable {
    case sideBySide = "Side by Side"
    case overlay = "Overlay"
    case difference = "Difference"

    var id: Self { self }
}

private enum TranslationLabPage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case testCases = "Test Cases"
    case evidence = "Evidence"
    case output = "Output"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .testCases: "checklist"
        case .evidence: "rectangle.on.rectangle.angled"
        case .output: "terminal"
        }
    }
}

private enum TranslationRAMRowScope: String, CaseIterable, Identifiable {
    case changes = "Changes Only"
    case all = "All Bytes"

    var id: Self { self }
}

private enum TranslationRAMQueryMode: String, CaseIterable, Identifiable {
    case text = "Text"
    case hex = "Hex Bytes"
    case address = "Address"

    var id: Self { self }

    var prompt: String {
        switch self {
        case .text: "ASCII or UTF-8 text"
        case .hex: "48 65 6C 6C 6F"
        case .address: "0x3A20"
        }
    }
}

enum TranslationRAMInspectorMode: String, CaseIterable, Identifiable {
    case bytes = "Bytes"
    case textBuffers = "Text Buffers"
    case pointerLeads = "Pointer Leads"

    var id: Self { self }
}

struct CheckpointRAMInspectorView: View {
    static let accessibilityIdentifier = "checkpoint-ram-inspector"
    static let textBufferReportAccessibilityIdentifier = "ram-text-buffer-report"
    static let pointerReportAccessibilityIdentifier = "checkpoint-ram-pointer-leads"
    static let minimumInteractiveDimension: CGFloat = 28
    static let privateTextAccessibilityMessage = "Decoded locally in this read-only view, these are heuristic leads from the selected checkpoint RAM. RAM-derived text is never included in Source-Free Diagnostics."

    static func pointerLeadAccessibilityLabel(
        targetAddress: String,
        change: String,
        originalCount: Int,
        patchedCount: Int
    ) -> String {
        "Near-pointer lead for \(change.lowercased()) text at \(targetAddress). Original has \(originalCount) reference site\(originalCount == 1 ? "" : "s"); Patched has \(patchedCount) reference site\(patchedCount == 1 ? "" : "s")."
    }

    static func pointerLeadAccessibilityIdentifier(targetOffset: Int) -> String {
        "pointer-lead-\(targetOffset)"
    }

    static func pointerAddressAccessibilityLabel(
        title: String,
        sourceAddress: String,
        status: String,
        targetAddress: String
    ) -> String {
        "\(title) reference at \(sourceAddress), \(status.lowercased()), points to text target \(targetAddress). Show in Bytes."
    }

    @Environment(\.dismiss) private var dismiss
    let comparison: TranslationRAMComparison?
    let issue: String?
    let textReport: TranslationRAMTextReport?
    let textIssue: String?
    let pointerReport: TranslationRAMPointerReport?
    let pointerIssue: String?
    let isLoading: Bool

    @State private var inspectorMode: TranslationRAMInspectorMode = .bytes
    @State private var rowScope: TranslationRAMRowScope = .changes
    @State private var queryMode: TranslationRAMQueryMode = .text
    @State private var query = ""
    @State private var searchHits: [TranslationRAMSearchHit] = []
    @State private var searchIssue: String?
    @State private var searchSummary: String?
    @State private var selectedRowOffset: Int?

    init(
        comparison: TranslationRAMComparison?,
        issue: String?,
        textReport: TranslationRAMTextReport?,
        textIssue: String?,
        pointerReport: TranslationRAMPointerReport? = nil,
        pointerIssue: String? = nil,
        isLoading: Bool,
        initialMode: TranslationRAMInspectorMode = .bytes
    ) {
        self.comparison = comparison
        self.issue = issue
        self.textReport = textReport
        self.textIssue = textIssue
        self.pointerReport = pointerReport
        self.pointerIssue = pointerIssue
        self.isLoading = isLoading
        _inspectorMode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            inspectorHeader
            Divider()

            if isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Revalidating checkpoint RAM…")
                        .font(.headline)
                    Text("Both evidence manifests and RAM digests are checked again before comparison.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let comparison {
                comparisonWorkspace(comparison)
            } else {
                ContentUnavailableView {
                    Label("RAM Inspection Unavailable", systemImage: "memorychip")
                } description: {
                    Text(issue ?? "The selected evidence pair could not be inspected.")
                } actions: {
                    Button("Close", action: dismiss.callAsFunction)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 980, idealWidth: 1_120, minHeight: 680, idealHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    private var inspectorHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.8), .purple.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "memorychip.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Checkpoint RAM")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Original and Patched at the same exact-route endpoint")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done", action: dismiss.callAsFunction)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private func comparisonWorkspace(_ comparison: TranslationRAMComparison) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("RAM inspector view", selection: $inspectorMode) {
                    ForEach(TranslationRAMInspectorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
                .accessibilityIdentifier("checkpoint-ram-inspector-mode")

                Text(inspectorModeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            switch inspectorMode {
            case .bytes:
                byteComparisonWorkspace(comparison)
            case .textBuffers:
                textBufferWorkspace(comparison)
            case .pointerLeads:
                pointerLeadWorkspace(comparison)
            }
        }
    }

    private var inspectorModeDescription: String {
        switch inspectorMode {
        case .bytes:
            "Exact bytes, changed ranges, and manual search"
        case .textBuffers:
            "Bounded ASCII and Shift-JIS buffer leads"
        case .pointerLeads:
            "Potential 16-bit references to changed text buffers"
        }
    }

    private func byteComparisonWorkspace(_ comparison: TranslationRAMComparison) -> some View {
        HStack(spacing: 0) {
            rangeSidebar(comparison)
                .frame(width: 244)
            Divider()
            comparisonTable(comparison)
        }
    }

    @ViewBuilder
    private func textBufferWorkspace(_ comparison: TranslationRAMComparison) -> some View {
        if let textReport {
            textBufferReport(textReport, comparison: comparison)
        } else {
            ContentUnavailableView {
                Label("Text-Buffer Analysis Unavailable", systemImage: "text.magnifyingglass")
            } description: {
                Text(textIssue ?? "The bounded text scanner could not analyze this RAM pair.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func textBufferReport(
        _ report: TranslationRAMTextReport,
        comparison: TranslationRAMComparison
    ) -> some View {
        let modifiedCount = report.changes.filter { $0.kind == .modified }.count
        let addedCount = report.changes.filter { $0.kind == .added }.count
        let removedCount = report.changes.filter { $0.kind == .removed }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ramMetric(
                    value: report.changes.count.formatted(),
                    label: "Changed buffers",
                    symbol: "text.badge.checkmark"
                )
                ramMetric(
                    value: modifiedCount.formatted(),
                    label: "Modified",
                    symbol: "arrow.left.arrow.right"
                )
                ramMetric(
                    value: addedCount.formatted(),
                    label: "Added",
                    symbol: "plus.circle"
                )
                ramMetric(
                    value: removedCount.formatted(),
                    label: "Removed",
                    symbol: "minus.circle"
                )
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Private RAM-derived text")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(Self.privateTextAccessibilityMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("Frame \(comparison.originalFrameNumber)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(13)
            .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)

            if report.originalWasTruncated || report.patchedWasTruncated {
                Label(
                    "The bounded scan reached its candidate limit. Refine the checkpoint or use Bytes search for complete manual inspection.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if report.changes.isEmpty {
                ContentUnavailableView {
                    Label("No Changed Text Buffers", systemImage: "text.badge.checkmark")
                } description: {
                    Text(
                        report.originalCandidates.isEmpty && report.patchedCandidates.isEmpty
                            ? "No terminated printable ASCII or Shift-JIS buffers met the bounded scanner’s confidence threshold."
                            : "The scanner found the same candidate text buffers in Original and Patched RAM."
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(report.changes) { change in
                            textBufferChangeCard(change)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Label(
                "A decoded buffer is a debugging lead, not proof of script ownership, glyph mapping, or source-ROM location.",
                systemImage: "lightbulb.min"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .accessibilityIdentifier(Self.textBufferReportAccessibilityIdentifier)
    }

    private func textBufferChangeCard(_ change: TranslationRAMTextChange) -> some View {
        let color = textBufferColor(change.kind)
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label(textBufferStatus(change.kind), systemImage: textBufferSymbol(change.kind))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.12), in: Capsule())
                Text(address(change.offset))
                    .font(.caption.monospaced().weight(.semibold))
                Text(textBufferEncoding(change))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                textBufferLane(
                    title: "Original",
                    candidate: change.original,
                    color: .cyan
                )
                Image(systemName: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
                    .accessibilityHidden(true)
                textBufferLane(
                    title: "Patched",
                    candidate: change.patched,
                    color: .purple
                )
            }
        }
        .padding(13)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.25))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(textBufferAccessibilityLabel(change))
    }

    private func textBufferLane(
        title: String,
        candidate: TranslationRAMTextCandidate?,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            if let candidate {
                Text(candidate.text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(candidate.byteCount) bytes · \(textBufferEncoding(candidate.encoding)) · terminator \(candidate.terminator.rawValue)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Not present")
                    .font(.body.italic())
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }

    private func textBufferStatus(_ kind: TranslationRAMTextChangeKind) -> String {
        switch kind {
        case .added: "Added"
        case .removed: "Removed"
        case .modified: "Modified"
        }
    }

    private func textBufferSymbol(_ kind: TranslationRAMTextChangeKind) -> String {
        switch kind {
        case .added: "plus.circle.fill"
        case .removed: "minus.circle.fill"
        case .modified: "arrow.left.arrow.right.circle.fill"
        }
    }

    private func textBufferColor(_ kind: TranslationRAMTextChangeKind) -> Color {
        switch kind {
        case .added: .green
        case .removed: .orange
        case .modified: .purple
        }
    }

    private func textBufferEncoding(_ change: TranslationRAMTextChange) -> String {
        let encodings = [change.original?.encoding, change.patched?.encoding]
            .compactMap { $0 }
        guard let first = encodings.first else { return "Unknown encoding" }
        if encodings.allSatisfy({ $0 == first }) {
            return textBufferEncoding(first)
        }
        return encodings.map { textBufferEncoding($0) }.joined(separator: " → ")
    }

    private func textBufferEncoding(_ encoding: TranslationRAMTextEncoding) -> String {
        switch encoding {
        case .ascii: "ASCII"
        case .shiftJIS: "Shift-JIS"
        }
    }

    private func textBufferAccessibilityLabel(_ change: TranslationRAMTextChange) -> String {
        let original = change.original?.text ?? "not present"
        let patched = change.patched?.text ?? "not present"
        return "\(textBufferStatus(change.kind)) text buffer at \(address(change.offset)), \(textBufferEncoding(change)). Original: \(original). Patched: \(patched)."
    }

    @ViewBuilder
    private func pointerLeadWorkspace(_ comparison: TranslationRAMComparison) -> some View {
        if let pointerReport {
            pointerLeadReport(pointerReport, comparison: comparison)
        } else {
            ContentUnavailableView {
                Label("Pointer-Lead Analysis Unavailable", systemImage: "arrow.triangle.branch")
            } description: {
                Text(pointerIssue ?? "The bounded pointer scanner could not analyze this RAM pair.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func pointerLeadReport(
        _ report: TranslationRAMPointerReport,
        comparison: TranslationRAMComparison
    ) -> some View {
        let visibleLeads = report.leadsWithReferences
        let stableCount = report.leads.reduce(0) { $0 + $1.stableReferenceOffsets.count }
        let addedCount = report.leads.reduce(0) { $0 + $1.addedReferenceOffsets.count }
        let removedCount = report.leads.reduce(0) { $0 + $1.removedReferenceOffsets.count }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ramMetric(
                    value: visibleLeads.count.formatted(),
                    label: "Referenced buffers",
                    symbol: "text.line.first.and.arrowtriangle.forward"
                )
                ramMetric(
                    value: stableCount.formatted(),
                    label: "Stable sites",
                    symbol: "equal.circle"
                )
                ramMetric(
                    value: addedCount.formatted(),
                    label: "Added sites",
                    symbol: "plus.circle"
                )
                ramMetric(
                    value: removedCount.formatted(),
                    label: "Removed sites",
                    symbol: "minus.circle"
                )
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title3)
                    .foregroundStyle(.indigo)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Near-pointer leads")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("This read-only scan finds little-endian 16-bit RAM values equal to changed text-buffer addresses. Select a site to inspect its exact bytes; confirm ownership with runtime tracing before changing a ROM.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("Frame \(comparison.originalFrameNumber)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(13)
            .background(.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)

            if report.wasTruncated {
                Label(
                    "The bounded scan reached a target or reference limit. These leads are incomplete; use Bytes search or a tracing emulator for deeper analysis.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if visibleLeads.isEmpty {
                ContentUnavailableView {
                    Label("No Near-Pointer Leads", systemImage: "arrow.triangle.branch")
                } description: {
                    Text("No 16-bit little-endian values in this checkpoint RAM pair matched the changed text-buffer addresses. The game may use segmented, indirect, encoded, or register-held references.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleLeads) { lead in
                            pointerLeadCard(lead)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Label(
                "Pointer-shaped values are ranked leads, not proof of a source pointer, segment, mapper bank, or ROM address. RAM-derived analysis stays out of Source-Free Diagnostics.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .accessibilityIdentifier(Self.pointerReportAccessibilityIdentifier)
    }

    private func pointerLeadCard(_ lead: TranslationRAMPointerLead) -> some View {
        let change = textReport?.changes.first { $0.offset == lead.targetOffset }
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label("Text target", systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                Text(address(lead.targetOffset))
                    .font(.caption.monospaced().weight(.semibold))
                Text(textBufferStatus(lead.textChangeKind))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(textBufferColor(lead.textChangeKind))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(textBufferColor(lead.textChangeKind).opacity(0.11), in: Capsule())
                Spacer()
                Text("\(lead.originalReferenceOffsets.count) → \(lead.patchedReferenceOffsets.count) sites")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let change {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(change.original?.text ?? "Not present")
                        .foregroundStyle(change.original == nil ? .tertiary : .primary)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(change.patched?.text ?? "Not present")
                        .foregroundStyle(change.patched == nil ? .tertiary : .primary)
                }
                .font(.callout.monospaced())
                .lineLimit(2)
                .textSelection(.enabled)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Original: \(change.original?.text ?? "not present"). Patched: \(change.patched?.text ?? "not present").")
            }

            HStack(alignment: .top, spacing: 12) {
                pointerReferenceLane(
                    title: "Original",
                    offsets: lead.originalReferenceOffsets,
                    counterpart: Set(lead.patchedReferenceOffsets),
                    targetOffset: lead.targetOffset,
                    role: .original
                )
                pointerReferenceLane(
                    title: "Patched",
                    offsets: lead.patchedReferenceOffsets,
                    counterpart: Set(lead.originalReferenceOffsets),
                    targetOffset: lead.targetOffset,
                    role: .patched
                )
            }
        }
        .padding(13)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.indigo.opacity(0.22))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            Self.pointerLeadAccessibilityLabel(
                targetAddress: address(lead.targetOffset),
                change: textBufferStatus(lead.textChangeKind),
                originalCount: lead.originalReferenceOffsets.count,
                patchedCount: lead.patchedReferenceOffsets.count
            )
        )
        .accessibilityIdentifier(
            Self.pointerLeadAccessibilityIdentifier(targetOffset: lead.targetOffset)
        )
    }

    private func pointerReferenceLane(
        title: String,
        offsets: [Int],
        counterpart: Set<Int>,
        targetOffset: Int,
        role: TranslationRAMSearchRole
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(role == .original ? .cyan : .purple)
            if offsets.isEmpty {
                Text("No matching near pointers")
                    .font(.caption.italic())
                    .foregroundStyle(.tertiary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 6)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(offsets, id: \.self) { sourceOffset in
                        let isStable = counterpart.contains(sourceOffset)
                        let status = isStable ? "Stable" : (role == .original ? "Removed" : "Added")
                        Button {
                            showPointerBytes(sourceOffset: sourceOffset, targetOffset: targetOffset)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isStable ? "equal.circle" : (role == .original ? "minus.circle" : "plus.circle"))
                                    .accessibilityHidden(true)
                                Text(address(sourceOffset))
                                    .font(.caption.monospaced().weight(.semibold))
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .frame(minHeight: Self.minimumInteractiveDimension)
                        .contentShape(Rectangle())
                        .tint(isStable ? .secondary : (role == .original ? .orange : .green))
                        .help("\(status) \(title.lowercased()) pointer-shaped value at \(address(sourceOffset)); show in Bytes")
                        .accessibilityLabel(
                            Self.pointerAddressAccessibilityLabel(
                                title: title,
                                sourceAddress: address(sourceOffset),
                                status: status,
                                targetAddress: address(targetOffset)
                            )
                        )
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            (role == .original ? Color.cyan : Color.purple).opacity(0.05),
            in: RoundedRectangle(cornerRadius: 9)
        )
    }

    private func showPointerBytes(sourceOffset: Int, targetOffset: Int) {
        rowScope = .all
        queryMode = .address
        query = address(sourceOffset)
        searchHits = []
        searchIssue = nil
        searchSummary = "Pointer lead \(address(sourceOffset)) → text at \(address(targetOffset))"
        selectedRowOffset = rowOffset(containing: sourceOffset)
        inspectorMode = .bytes
    }

    private func rangeSidebar(_ comparison: TranslationRAMComparison) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Changed ranges")
                    .font(.headline)
                Text("\(comparison.changeRanges.count) contiguous region\(comparison.changeRanges.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if comparison.changeRanges.isEmpty {
                ContentUnavailableView(
                    "Byte-identical",
                    systemImage: "equal.circle",
                    description: Text("No internal-RAM bytes changed at this checkpoint.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(comparison.changeRanges) { range in
                            Button {
                                selectedRowOffset = rowOffset(containing: range.startOffset)
                            } label: {
                                HStack {
                                    Text(address(range.startOffset))
                                        .font(.caption.monospaced().weight(.semibold))
                                    Spacer()
                                    Text(range.length.formatted())
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .background(
                                    selectedRowOffset == rowOffset(containing: range.startOffset)
                                        ? Color.accentColor.opacity(0.13)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("\(address(range.startOffset))–\(address(range.endOffset)), \(range.length) changed bytes")
                        }
                    }
                }
            }

            Spacer(minLength: 8)
            Label(
                "Read-only diagnostic. A changed address is a lead, not proof of text, glyph, or ROM ownership.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.background.secondary)
    }

    private func comparisonTable(_ comparison: TranslationRAMComparison) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ramMetric(
                    value: ByteCountFormatter.string(
                        fromByteCount: Int64(comparison.byteCount),
                        countStyle: .memory
                    ),
                    label: "Snapshot",
                    symbol: "memorychip"
                )
                ramMetric(
                    value: comparison.changedByteCount.formatted(),
                    label: "Changed bytes",
                    symbol: "plusminus"
                )
                ramMetric(
                    value: comparison.changedFraction.formatted(.percent.precision(.fractionLength(3))),
                    label: "Changed",
                    symbol: "percent"
                )
                ramMetric(
                    value: "Frame \(comparison.originalFrameNumber)",
                    label: "Exact endpoint",
                    symbol: "scope"
                )
            }

            HStack(spacing: 10) {
                Picker("Rows", selection: $rowScope) {
                    ForEach(TranslationRAMRowScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Divider()
                    .frame(height: 22)

                Picker("Search", selection: $queryMode) {
                    ForEach(TranslationRAMQueryMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 112)

                TextField(queryMode.prompt, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { performSearch(comparison) }

                Button("Find", systemImage: "magnifyingglass") {
                    performSearch(comparison)
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let searchIssue {
                Label(searchIssue, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let searchSummary {
                HStack(spacing: 8) {
                    Text(searchSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(searchHits.prefix(80)) { hit in
                                Button("\(hit.role.rawValue) \(address(hit.offset))") {
                                    rowScope = .all
                                    selectedRowOffset = rowOffset(containing: hit.offset)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(hit.role == .original ? .cyan : .purple)
                            }
                        }
                    }
                }
            }

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        let offsets = rowScope == .changes
                            ? comparison.changedRowOffsets
                            : comparison.allRowOffsets
                        if offsets.isEmpty {
                            ContentUnavailableView(
                                "No Changed Rows",
                                systemImage: "equal.circle",
                                description: Text("Switch to All Bytes to inspect the complete snapshot.")
                            )
                            .frame(minWidth: 650, minHeight: 300)
                        } else {
                            ForEach(offsets, id: \.self) { offset in
                                if let row = comparison.row(at: offset) {
                                    ramRow(row, selected: selectedRowOffset == offset)
                                        .id(offset)
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.separator.opacity(0.5))
                }
                .onChange(of: selectedRowOffset) { _, offset in
                    guard let offset else { return }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo(offset, anchor: .center)
                    }
                }
            }
        }
        .padding(18)
    }

    private func ramMetric(value: String, label: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    private func ramRow(_ row: TranslationRAMRow, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ramByteLine(
                role: "Original",
                bytes: row.original,
                counterpart: row.patched,
                color: .cyan
            )
            ramByteLine(
                role: "Patched",
                bytes: row.patched,
                counterpart: row.original,
                color: .purple
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            selected ? Color.accentColor.opacity(0.11) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(alignment: .topLeading) {
            Text(address(row.offset))
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(.secondary)
                .offset(x: 8, y: 7)
        }
    }

    private func ramByteLine(
        role: String,
        bytes: [UInt8],
        counterpart: [UInt8],
        color: Color
    ) -> some View {
        HStack(spacing: 3) {
            Text(role)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 58, alignment: .leading)
                .padding(.leading, 60)

            ForEach(bytes.indices, id: \.self) { index in
                let changed = counterpart.indices.contains(index) && bytes[index] != counterpart[index]
                Text(String(format: "%02X", bytes[index]))
                    .font(.caption.monospaced().weight(changed ? .bold : .regular))
                    .foregroundStyle(changed ? color : Color.primary)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(
                        changed ? color.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 3)
                    )
            }

            Text(ascii(bytes))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func performSearch(_ comparison: TranslationRAMComparison) {
        searchIssue = nil
        searchSummary = nil
        searchHits = []
        do {
            switch queryMode {
            case .text:
                guard let pattern = query.data(using: .utf8), !pattern.isEmpty else {
                    throw TranslationRAMInspectionError.emptySearch
                }
                searchHits = try comparison.search(pattern)
            case .hex:
                searchHits = try comparison.search(
                    TranslationRAMComparison.hexPattern(query)
                )
            case .address:
                let offset = try comparison.validatedAddress(query)
                rowScope = .all
                selectedRowOffset = rowOffset(containing: offset)
                searchSummary = "Address \(address(offset))"
                return
            }

            if let first = searchHits.first {
                rowScope = .all
                selectedRowOffset = rowOffset(containing: first.offset)
            }
            searchSummary = searchHits.isEmpty
                ? "No exact matches"
                : "\(searchHits.count) exact match\(searchHits.count == 1 ? "" : "es")"
        } catch {
            searchIssue = error.localizedDescription
        }
    }

    private func rowOffset(containing offset: Int) -> Int {
        (offset / TranslationRAMComparison.rowByteCount)
            * TranslationRAMComparison.rowByteCount
    }

    private func address(_ offset: Int) -> String {
        String(format: "0x%04X", offset)
    }

    private func ascii(_ bytes: [UInt8]) -> String {
        String(bytes.map { byte in
            (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "·"
        })
    }
}

enum TranslationLabOverviewAccessibility {
    static let page = "translation-overview-page"
    static let workflow = "translation-lab-overview-workflow"
    static let workflowLabel = "Deterministic route testing workflow"
    static let readinessMetrics = "translation-lab-overview-readiness-metrics"
    static let currentAction = "translation-lab-overview-current-action"
    static let currentActionLabel = "Current route testing action"
    static let recordTest = "translation-lab-overview-record-test"
    static let findFirstChange = "translation-lab-overview-find-first-change"
    static let verifyRoute = "translation-lab-overview-verify-route"
    static let refreshReadiness = "translation-lab-overview-refresh-readiness"

    static func workflowStep(_ number: String) -> String {
        "translation-lab-overview-workflow-step-\(number)"
    }
}

@MainActor
final class TranslationLabOverviewGeometryProbe {
    static let coordinateSpace = "translation-lab-overview-scroll-viewport"

    private(set) var viewportFrame = CGRect.zero
    private(set) var elementFrames: [String: CGRect] = [:]

    func recordViewport(_ frame: CGRect) {
        viewportFrame = frame
    }

    func recordElement(identifier: String, frame: CGRect) {
        elementFrames[identifier] = frame
    }
}

private struct TranslationLabOverviewViewportGeometryReader: View {
    let probe: TranslationLabOverviewGeometryProbe?

    var body: some View {
        GeometryReader { proxy in
            let frame = CGRect(origin: .zero, size: proxy.size)
            Color.clear
                .onAppear { probe?.recordViewport(frame) }
                .onChange(of: frame) { _, value in probe?.recordViewport(value) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TranslationLabOverviewElementGeometryReader: View {
    let identifier: String
    let probe: TranslationLabOverviewGeometryProbe?

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(
                in: .named(TranslationLabOverviewGeometryProbe.coordinateSpace)
            )
            Color.clear
                .onAppear {
                    probe?.recordElement(identifier: identifier, frame: frame)
                }
                .onChange(of: frame) { _, value in
                    probe?.recordElement(identifier: identifier, frame: value)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TranslationLabView: View {
    @Bindable var model: AppModel
    var overviewGeometryProbe: TranslationLabOverviewGeometryProbe? = nil
    @SceneStorage("translationLabPage") private var translationLabPageRaw = TranslationLabPage.overview.rawValue
    @State private var pendingWorkspaceAnchor: String?
    @State private var evidenceComparisonMode: EvidenceComparisonMode = {
        switch ProcessInfo.processInfo.environment[
            "SWAN_SONG_EVIDENCE_COMPARISON_MODE"
        ]?.lowercased() {
        case "overlay": .overlay
        case "difference": .difference
        default: .sideBySide
        }
    }()
    @State private var evidenceComparisonZoom: Double = {
        guard
            let value = ProcessInfo.processInfo.environment[
                "SWAN_SONG_EVIDENCE_COMPARISON_ZOOM"
            ].flatMap(Double.init),
            [1.0, 2.0, 4.0].contains(value)
        else { return 1.0 }
        return value
    }()
    @State private var evidenceOverlayAmount = 0.5

    private var translationLabPage: TranslationLabPage {
        TranslationLabPage(rawValue: translationLabPageRaw) ?? .overview
    }

    private var translationLabPageBinding: Binding<TranslationLabPage> {
        Binding(
            get: { translationLabPage },
            set: { translationLabPageRaw = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            if let project = model.translationProject {
                translationProjectWorkspace(project)
            } else {
                ContentUnavailableView {
                    Label("Add Translation Projects", systemImage: "character.book.closed")
                } description: {
                    Text("Choose one project or link an entire private toolkit. SwanSong will keep every game’s status, test routes, and captures together.")
                } actions: {
                    Button("Add Project or Toolkit…", action: model.chooseTranslationProject)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
        .navigationTitle("Translation Lab")
        .tint(SwanTheme.accent)
        .toolbar {
            if model.translationProject != nil {
                ToolbarItem(placement: .principal) {
                    Picker("Translation Lab Page", selection: translationLabPageBinding) {
                        ForEach(TranslationLabPage.allCases) { page in
                            Label(page.rawValue, systemImage: page.symbol)
                                .tag(page)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 420)
                    .accessibilityLabel("Translation Lab Page")
                    .accessibilityValue(translationLabPage.rawValue)
                    .accessibilityIdentifier("translation-lab-page-picker")
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Record New Test", systemImage: "record.circle") {
                        translationLabPageRaw = TranslationLabPage.testCases.rawValue
                        model.startCleanBootTranslationTest()
                    }
                    .disabled(
                        !model.engineCanExecute
                            || !model.translationOriginalROMAvailable
                            || model.translationToolIsRunning
                            || model.isPlaying
                    )
                    .help("Record a deterministic route from a clean Original boot")
                    .accessibilityIdentifier("translation-record-new-test")

                    Menu {
                        Button("Run Original", systemImage: "play") {
                            model.playTranslationROM(.original)
                        }
                        .disabled(
                            !model.engineCanExecute
                                || !model.translationOriginalROMAvailable
                                || model.translationToolIsRunning
                                || model.isPlaying
                        )

                        Button("Build & Run Patched", systemImage: "hammer.fill") {
                            model.buildAndRunTranslation()
                        }
                        .disabled(!model.engineCanExecute || model.translationToolIsRunning || model.isPlaying)

                        Button("Run Current Patch", systemImage: "play.fill") {
                            model.playTranslationROM(.patched)
                        }
                        .disabled(
                            !model.engineCanExecute
                                || !model.translationPatchedROMAvailable
                                || model.translationToolIsRunning
                                || model.isPlaying
                        )
                    } label: {
                        Label("Run", systemImage: "play.circle")
                    }
                    .help("Run Original or Patched")

                    Button("Check Project", systemImage: "checkmark.shield") {
                        model.checkTranslationProject()
                    }
                    .disabled(model.translationToolIsRunning)
                    .help("Run the guarded project checks")
                    .accessibilityIdentifier("translation-check-project")

                    Button("Refresh Status", systemImage: "arrow.clockwise") {
                        model.refreshTranslationStatus()
                    }
                    .disabled(model.translationToolIsRunning)
                    .help("Refresh project status")
                    .accessibilityIdentifier("translation-refresh-status")

                    if model.translationToolIsRunning {
                        ProgressView()
                            .controlSize(.small)
                            .help(model.translationToolPhase ?? "Running toolkit stage")
                            .accessibilityLabel("Translation toolkit is running")
                            .accessibilityValue(model.translationToolPhase ?? "Running toolkit stage")
                    }

                    Menu {
                        Button("Add Project or Toolkit…", systemImage: "plus", action: model.chooseTranslationProject)
                        Button("Show Project in Finder", systemImage: "folder", action: model.revealTranslationProject)
                        if model.lastTranslationEvidenceURL != nil {
                            Button("Show Last Evidence", systemImage: "camera.viewfinder", action: model.revealLastTranslationEvidence)
                        }
                        Divider()
                        Button("Unlink Project", systemImage: "link.badge.minus", role: .destructive, action: model.unlinkTranslationProject)
                    } label: {
                        Label("Project Actions", systemImage: "ellipsis.circle")
                    }
                    .help("Project Actions")
                    .accessibilityIdentifier("translation-project-actions")
                }
            }
        }
        .sheet(isPresented: $model.isTranslationRAMInspectorPresented) {
            CheckpointRAMInspectorView(
                comparison: model.translationRAMComparison,
                issue: model.translationRAMInspectionIssue,
                textReport: model.translationRAMTextReport,
                textIssue: model.translationRAMTextInspectionIssue,
                pointerReport: model.translationRAMPointerReport,
                pointerIssue: model.translationRAMPointerInspectionIssue,
                isLoading: model.translationRAMInspectionIsLoading
            )
        }
        .sheet(
            isPresented: Binding(
                get: { model.isTranslationVisualDivergencePresented },
                set: { isPresented in
                    if !isPresented {
                        model.dismissTranslationVisualDivergence()
                    }
                }
            )
        ) {
            TranslationVisualDivergenceView(model: model)
        }
        .sheet(
            isPresented: Binding(
                get: { model.isTranslationTextIntakePresented },
                set: { isPresented in
                    if !isPresented {
                        model.dismissTranslationTextIntake()
                    }
                }
            )
        ) {
            TranslationTextIntakeView(model: model)
                .interactiveDismissDisabled(model.translationTextIntakeIsRecognizing)
        }
        .task {
            if model.translationProject != nil,
               model.translationReadiness == nil,
               !model.translationToolIsRunning,
               !model.hasAutomatedTranslationLaunch {
                model.refreshTranslationStatus()
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.035),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func translationProjectWorkspace(_ project: TranslationProject) -> some View {
        VStack(spacing: 0) {
            workspaceBar(project)
                .padding(.horizontal, 28)
                .padding(.vertical, 13)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Color.clear
                            .frame(height: 0)
                            .id("translation-page-top")
                        translationLabPageContent(project)
                    }
                    .padding(28)
                    .frame(maxWidth: 1060, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: TranslationLabOverviewGeometryProbe.coordinateSpace)
                .background(
                    TranslationLabOverviewViewportGeometryReader(
                        probe: overviewGeometryProbe
                    )
                )
                .onChange(of: translationLabPageRaw) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo("translation-page-top", anchor: .top)
                    }
                }
                .onChange(of: pendingWorkspaceAnchor) { _, destination in
                    guard let destination else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        withAnimation(.easeInOut(duration: 0.28)) {
                            proxy.scrollTo(destination, anchor: .top)
                        }
                        if pendingWorkspaceAnchor == destination {
                            pendingWorkspaceAnchor = nil
                        }
                    }
                }
                .onChange(of: model.selectedTranslationEvidenceID) { previous, selected in
                    guard
                        previous != selected,
                        selected != nil,
                        translationLabPage == .evidence
                    else { return }
                    pendingWorkspaceAnchor = "translation-evidence-review"
                }
                .task {
                    let environment = ProcessInfo.processInfo.environment
                    let destination: (page: TranslationLabPage, anchor: String)
                    if environment["SWAN_SONG_OPEN_BASELINE_PANEL"] == "1" {
                        destination = (.evidence, "translation-baseline-controls")
                    } else if environment["SWAN_SONG_OPEN_EVIDENCE_REVIEW"] == "1" {
                        destination = (.evidence, "translation-evidence-review")
                    } else if environment["SWAN_SONG_OPEN_TEST_CASES"] == "1" {
                        destination = (.testCases, "translation-test-cases")
                    } else {
                        return
                    }
                    translationLabPageRaw = destination.page.rawValue
                    try? await Task.sleep(for: .milliseconds(350))
                    proxy.scrollTo(destination.anchor, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func translationLabPageContent(_ project: TranslationProject) -> some View {
        switch translationLabPage {
        case .overview:
            VStack(alignment: .leading, spacing: 20) {
                projectHeader(project)
                testLoop(project)
                readinessOverview
                safeguards
            }
            .accessibilityIdentifier(TranslationLabOverviewAccessibility.page)

        case .testCases:
            routeHistory
                .id("translation-test-cases")
                .accessibilityIdentifier("translation-test-cases-page")

        case .evidence:
            VStack(alignment: .leading, spacing: 20) {
                if model.translationEvidence.isEmpty {
                    ContentUnavailableView {
                        Label("No Evidence Yet", systemImage: "camera.viewfinder")
                    } description: {
                        Text("Record a deterministic test case, then verify Original and Patched to capture an exact-route pair.")
                    } actions: {
                        Button("Open Test Cases", systemImage: "checklist") {
                            translationLabPageRaw = TranslationLabPage.testCases.rawValue
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    evidenceHistory
                    evidenceReviewDesk
                        .id("translation-evidence-review")
                }
            }
            .accessibilityIdentifier("translation-evidence-page")

        case .output:
            VStack(alignment: .leading, spacing: 16) {
                if model.translationToolIsRunning {
                    toolkitRunningStatus
                }

                if model.translationCommandOutput.isEmpty {
                    ContentUnavailableView {
                        Label("No Toolkit Output", systemImage: "terminal")
                    } description: {
                        Text("Run Check Project or refresh the linked project to inspect guarded toolkit output here.")
                    } actions: {
                        HStack {
                            Button("Check Project", systemImage: "checkmark.shield") {
                                model.checkTranslationProject()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.translationToolIsRunning)

                            Button("Refresh Status", systemImage: "arrow.clockwise") {
                                model.refreshTranslationStatus()
                            }
                            .disabled(model.translationToolIsRunning)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    toolkitOutput
                }
            }
            .accessibilityIdentifier("translation-output-page")
        }
    }

    private func openTranslationEvidence(
        _ evidenceID: TranslationEvidenceSummary.ID? = nil,
        anchor: String = "translation-evidence-review"
    ) {
        if let evidenceID {
            model.selectTranslationEvidence(evidenceID)
        }
        translationLabPageRaw = TranslationLabPage.evidence.rawValue
        pendingWorkspaceAnchor = anchor
    }

    private func workspaceBar(_ project: TranslationProject) -> some View {
        HStack(spacing: 12) {
            Label(
                model.translationProjects.count == 1
                    ? "1 private project"
                    : "\(model.translationProjects.count) private projects",
                systemImage: "books.vertical.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Menu {
                ForEach(model.translationProjects) { candidate in
                    Button {
                        model.selectTranslationProject(candidate.id)
                    } label: {
                        if candidate.id == project.id {
                            Label(candidate.title, systemImage: "checkmark")
                        } else {
                            Text(candidate.title)
                        }
                    }
                }
            } label: {
                Text(project.title)
                    .lineLimit(1)
                    .frame(maxWidth: 320, alignment: .leading)
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Button("Add Project or Toolkit", systemImage: "plus", action: model.chooseTranslationProject)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 4)
    }

    private func projectHeader(_ project: TranslationProject) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.indigo, .purple.opacity(0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white)
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        Text(project.title)
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        readinessBadge
                    }
                    Text("\(project.platform) · \(project.sourceLanguage.uppercased()) → \(project.targetLanguage.uppercased())")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(project.rootURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.separator.opacity(0.45))
        }
    }

    private var readinessOverview: some View {
        Group {
            if let readiness = model.translationReadiness {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Project readiness")
                                .font(.title3.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text(readiness.headline)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int((readiness.completionFraction * 100).rounded()))% of stages complete")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(readinessColor(readiness.status))
                    }

                    ProgressView(value: readiness.completionFraction)
                        .tint(readinessColor(readiness.status))

                    if let metrics = readiness.metrics {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 210), spacing: 10)],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            readinessMetric(
                                value: "\(metrics.translated) / \(metrics.extracted)",
                                label: "Strings translated",
                                symbol: "text.quote"
                            )
                            readinessMetric(
                                value: "\(Int((metrics.translationFraction * 100).rounded()))%",
                                label: "Corpus coverage",
                                symbol: "chart.bar.fill"
                            )
                            readinessMetric(
                                value: "\(metrics.tableEntries)",
                                label: "Table entries",
                                symbol: "character.cursor.ibeam"
                            )
                            readinessMetric(
                                value: "\(metrics.fixedExtractors) + \(metrics.pointerExtractors)",
                                label: "Text extractors",
                                symbol: "point.3.connected.trianglepath.dotted"
                            )
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Project readiness metrics")
                        .accessibilityIdentifier(TranslationLabOverviewAccessibility.readinessMetrics)
                    }

                    if !readiness.phases.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 210), spacing: 10)],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(readiness.phases) { phase in
                                readinessPhase(phase)
                            }
                        }
                    }

                    if !readiness.nextActions.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Next actions")
                                .font(.headline)
                            ForEach(readiness.nextActions) { action in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(action.priority.rawValue)
                                        .font(.caption2.monospaced().weight(.bold))
                                        .foregroundStyle(actionPriorityColor(action.priority))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(actionPriorityColor(action.priority).opacity(0.12), in: Capsule())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(action.detail)
                                            .font(.callout)
                                        if let command = action.command {
                                            Text(command)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if model.translationToolIsRunning {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading the toolkit’s structured project status…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Readiness has not been checked")
                            .font(.headline)
                        Text("Refresh to read the project’s current toolkit status.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        model.refreshTranslationStatus()
                    }
                    .accessibilityIdentifier(TranslationLabOverviewAccessibility.refreshReadiness)
                }
                .padding(18)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func readinessMetric(value: String, label: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func readinessPhase(_ phase: TranslationReadinessPhase) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: readinessSymbol(phase.status))
                .foregroundStyle(readinessColor(phase.status))
            VStack(alignment: .leading, spacing: 3) {
                Text(phase.name)
                    .font(.subheadline.weight(.semibold))
                Text(phase.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let command = phase.nextCommand {
                    Text(command)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(command)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var routeHistory: some View {
        historySection(
            title: "Route Tests",
            subtitle: "Record from a clean boot, save the exact target frame, then replay the same inputs against Original and Patched.",
            count: model.translationRoutes.count
        ) {
            VStack(spacing: 10) {
                if model.translationRoutes.isEmpty {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                            Image(systemName: "record.circle")
                                .font(.title2)
                                .foregroundStyle(.orange)
                        }
                        .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No route tests yet")
                                .font(.headline)
                            Text("Start Original from frame 1, play to a useful screen, then save that exact checkpoint.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Record New Test…", systemImage: "record.circle") {
                            model.startCleanBootTranslationTest()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            !model.engineCanExecute
                                || !model.translationOriginalROMAvailable
                                || model.translationToolIsRunning
                                || model.isPlaying
                        )
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    translationSuiteDashboard
                    ForEach(model.translationRoutes) { summary in
                        routeTestCaseRow(summary)
                    }
                    if let selected = model.selectedTranslationRouteSummary {
                        routeTestCaseEditor(selected)
                    }
                }
            }
        }
    }

    private var translationSuiteDashboard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.cyan.opacity(0.2), .purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "checklist.checked")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Batch A/B verification")
                        .font(.headline)
                    if model.translationSuiteIsActive {
                        Text(
                            "Case \((model.translationSuiteCurrentCaseIndex ?? 0) + 1) of \(model.translationSuiteTotalCaseCount) · \(model.translationSuiteCurrentCaseName ?? "Preparing route")"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    } else if let run = model.latestTranslationSuiteRun {
                        Text(
                            "Last completed \(run.completedAt.formatted(date: .abbreviated, time: .shortened)) · \(run.cases.count) verified cases"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Build once, then replay every saved route against Original and Patched.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if model.translationSuiteIsActive {
                    Text("\(model.translationSuiteCaseResults.count) / \(model.translationSuiteTotalCaseCount)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Button(
                        model.latestTranslationSuiteRun == nil ? "Run All Cases" : "Run Again",
                        systemImage: "play.fill"
                    ) {
                        model.verifyTranslationSuite()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canVerifyTranslationSuite)
                    .help(
                        model.translationSuiteBlockingIssue
                            ?? "Run guarded QA and strict pack once, then capture a fresh exact-route A/B pair for every test case."
                    )
                }
            }

            if model.translationSuiteIsActive {
                ProgressView(value: model.translationSuiteProgress ?? 0)
                    .tint(.cyan)
            } else if let issue = model.translationSuiteBlockingIssue,
                      !model.translationRoutes.isEmpty {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let run = model.latestTranslationSuiteRun {
                HStack(spacing: 8) {
                    suiteMetric(
                        value: "\(run.changedFromBaselineCount)",
                        label: "Changed",
                        symbol: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                    suiteMetric(
                        value: "\(run.stableAgainstBaselineCount)",
                        label: "Stable",
                        symbol: "checkmark.seal.fill",
                        color: .green
                    )
                    suiteMetric(
                        value: "\(run.unbaselinedCaseCount)",
                        label: "No baseline",
                        symbol: "scope",
                        color: .secondary
                    )
                    Text("Changed means the patched frame differs from its approved baseline and needs review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.cyan.opacity(0.055), Color.purple.opacity(0.055)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.cyan.opacity(0.28), .purple.opacity(0.28)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    private func suiteMetric(
        value: String,
        label: String,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.background.opacity(0.75), in: Capsule())
    }

    private func routeTestCaseRow(
        _ summary: TranslationRouteSummary
    ) -> some View {
        let selected = model.latestTranslationRouteURL?.path == summary.fileURL.path
        let coverage = model.translationTestCaseCoverage(for: summary)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                model.selectTranslationRoute(summary.id)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(testCaseStatusColor(coverage.status).opacity(0.12))
                        Image(systemName: coverage.status.symbol)
                            .font(.title3)
                            .foregroundStyle(testCaseStatusColor(coverage.status))
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(summary.testCase?.name ?? "Untitled route")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if let issue = summary.testCaseIssue {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help(issue)
                                    .accessibilityLabel("Test-case metadata issue")
                                    .accessibilityValue(issue)
                            }
                        }
                        Text(routeTestCaseSubtitle(summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        routeTestCaseMetadata(summary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    routeProofBadges(summary)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 12)
                    routeTestCaseControls(summary, coverage: coverage)
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 8) {
                    routeProofBadges(summary)
                    routeTestCaseControls(summary, coverage: coverage)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(
                    selected ? Color.accentColor.opacity(0.65) : Color.clear,
                    lineWidth: 1.5
                )
        }
        .help(selected ? "Selected test case" : "Select this route test case")
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func routeTestCaseMetadata(
        _ summary: TranslationRouteSummary
    ) -> some View {
        let frameCount = summary.route.totalFrames
        let changeCount = summary.route.events.count
        let target = summary.route.targetFrameNumber
        var compactParts = [
            "\(frameCount) frame\(frameCount == 1 ? "" : "s")",
        ]
        if let target {
            compactParts.append("Target \(target)")
        }
        compactParts.append("\(changeCount) change\(changeCount == 1 ? "" : "s")")
        compactParts.append(summary.route.recordedFrom.title)
        let compactSummary = compactParts.joined(separator: " · ")

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Label("\(frameCount) frames", systemImage: "film.stack")
                if let target {
                    Label("Target \(target)", systemImage: "scope")
                }
                Label("\(changeCount) changes", systemImage: "waveform.path.ecg")
                Text(summary.route.recordedFrom.title.uppercased())
            }
            .fixedSize(horizontal: true, vertical: false)

            Text(compactSummary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.tertiary)
        .accessibilityLabel(compactSummary)
    }

    @ViewBuilder
    private func routeProofBadges(_ summary: TranslationRouteSummary) -> some View {
        HStack(spacing: 7) {
            switch summary.route.proofEligibility {
            case .proofReady:
                baselineBadge(
                    "Clean Boot",
                    symbol: "power.circle.fill",
                    color: .green
                )
            case .legacyStartUnknown:
                baselineBadge(
                    "v1 · Re-record",
                    symbol: "clock.badge.exclamationmark",
                    color: .orange
                )
                .help(summary.route.proofEligibility.issue ?? "Re-record this route from a clean boot.")
            case .rtcStartUnknown:
                baselineBadge(
                    "v2 · Re-record RTC",
                    symbol: "clock.badge.exclamationmark",
                    color: .orange
                )
                .help(summary.route.proofEligibility.issue ?? "Re-record this route with the fixed UTC RTC seed.")
            case let .invalidV2(issue), let .invalidV3(issue):
                baselineBadge(
                    "Invalid Route · Repair or re-record",
                    symbol: "exclamationmark.shield.fill",
                    color: .red
                )
                .help(issue)
                .accessibilityLabel("Invalid route. Repair or re-record.")
                .accessibilityValue(issue)
            }
            routeBaselineBadge(summary)
        }
    }

    private func routeTestCaseControls(
        _ summary: TranslationRouteSummary,
        coverage: AppModel.TranslationTestCaseCoverage
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                routeCoverageLanes(coverage)
                routeReviewControl(coverage)
                routeLocateChangeControl(summary)
                routeVerifyControl(summary)
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .trailing, spacing: 8) {
                routeCoverageLanes(coverage)
                HStack(spacing: 10) {
                    routeReviewControl(coverage)
                    routeLocateChangeControl(summary)
                    routeVerifyControl(summary)
                }
            }
        }
    }

    private func routeCoverageLanes(
        _ coverage: AppModel.TranslationTestCaseCoverage
    ) -> some View {
        HStack(spacing: 6) {
            testCaseLane(
                "Original",
                captured: coverage.original != nil,
                color: .cyan
            )
            testCaseLane(
                "Patched",
                captured: coverage.patched != nil,
                color: .purple
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func routeReviewControl(
        _ coverage: AppModel.TranslationTestCaseCoverage
    ) -> some View {
        if let reviewEvidence = coverage.patched ?? coverage.original {
            Button {
                openTranslationEvidence(reviewEvidence.id)
            } label: {
                routeReviewLabel(coverage)
            }
            .buttonStyle(.plain)
            .help("Open this test case’s newest evidence review")
        } else {
            routeReviewLabel(coverage)
        }
    }

    private func routeReviewLabel(
        _ coverage: AppModel.TranslationTestCaseCoverage
    ) -> some View {
        Label(coverage.status.title, systemImage: coverage.status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(testCaseStatusColor(coverage.status))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func routeVerifyControl(
        _ summary: TranslationRouteSummary
    ) -> some View {
        Button("Verify", systemImage: "arrow.triangle.2.circlepath") {
            model.selectTranslationRoute(summary.id)
            translationLabPageRaw = TranslationLabPage.evidence.rawValue
            model.verifyLatestTranslationRoute()
        }
        .buttonStyle(.bordered)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(
            !model.engineCanExecute
                || model.isPlaying
                || model.translationToolIsRunning
                || !model.translationOriginalROMAvailable
                || summary.route.proofEligibility != .proofReady
        )
        .help(
            summary.route.proofEligibility.issue
                ?? "Verify this clean-boot route against Original and Patched"
        )
    }

    private func routeLocateChangeControl(
        _ summary: TranslationRouteSummary
    ) -> some View {
        Button("First Change", systemImage: "scope") {
            model.selectTranslationRoute(summary.id)
            model.locateFirstTranslationVisualChange()
        }
        .buttonStyle(.bordered)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(
            !model.engineCanExecute
                || model.isPlaying
                || model.translationToolIsRunning
                || model.translationVisualDivergenceIsRunning
                || !model.translationOriginalROMAvailable
                || !model.translationPatchedROMAvailable
                || summary.route.proofEligibility != .proofReady
        )
        .help(
            summary.route.proofEligibility.issue
                ?? "Replay both ROMs deterministically and locate their first changed game-raster frame"
        )
        .accessibilityIdentifier("translation-first-change-\(summary.id)")
    }

    @ViewBuilder
    private func routeBaselineBadge(_ summary: TranslationRouteSummary) -> some View {
        if let result = model.latestTranslationSuiteResult(for: summary),
           let comparison = result.baselineComparison {
            if comparison.hasVisualChanges {
                baselineBadge("Changed", symbol: "exclamationmark.triangle.fill", color: .orange)
            } else {
                baselineBadge("Stable", symbol: "checkmark.seal.fill", color: .green)
            }
        } else if let baseline = model.translationBaseline(for: summary) {
            if baseline.isIntact {
                baselineBadge("Baseline set", symbol: "scope", color: .indigo)
            } else {
                baselineBadge("Baseline issue", symbol: "exclamationmark.shield.fill", color: .red)
                    .help(baseline.integrityIssue ?? "The route baseline is not usable.")
            }
        } else {
            baselineBadge("No baseline", symbol: "scope", color: .secondary)
        }
    }

    private func baselineBadge(
        _ title: String,
        symbol: String,
        color: Color
    ) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
    }

    private func routeTestCaseEditor(
        _ summary: TranslationRouteSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Test-case details", systemImage: "pencil.and.list.clipboard")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Route \(summary.routeDigest.sha256.prefix(10))…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .help(summary.routeDigest.sha256)
            }

            TextField(
                "Test name — e.g. Chapter 2 shop overflow",
                text: $model.translationTestCaseName
            )
            .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 5) {
                Text("What should a reviewer check?")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.translationTestCaseNote)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 68, maxHeight: 90)
                    .background(.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(.separator.opacity(0.55))
                    }
                    .accessibilityLabel("Test case review note")
            }

            HStack {
                Label(
                    "Names and notes are editable sidecars; the hash-bound input route never changes.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Save Test Case", systemImage: "checkmark.circle.fill") {
                    model.saveSelectedTranslationTestCase()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !model.translationTestCaseHasChanges
                        || model.translationTestCaseName
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                )
            }

            if let issue = summary.testCaseIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func routeTestCaseSubtitle(
        _ summary: TranslationRouteSummary
    ) -> String {
        if let note = summary.testCase?.note, !note.isEmpty {
            return note
        }
        return "Recorded \(summary.route.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func testCaseLane(
        _ title: String,
        captured: Bool,
        color: Color
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: captured ? "checkmark.circle.fill" : "circle")
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(captured ? color : Color.secondary)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            (captured ? color : Color.secondary).opacity(captured ? 0.12 : 0.07),
            in: Capsule()
        )
    }

    private func testCaseStatusColor(
        _ status: AppModel.TranslationTestCaseStatus
    ) -> Color {
        switch status {
        case .notRun: .secondary
        case .partial: .orange
        case .readyForReview: .blue
        case .needsWork: .orange
        case .approved: .green
        case .integrityIssue: .red
        }
    }

    @ViewBuilder
    private var evidenceHistory: some View {
        if !model.translationEvidence.isEmpty {
            historySection(
                title: "Capture evidence",
                subtitle: evidenceHistorySubtitle,
                count: model.translationEvidence.count
            ) {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(model.translationEvidence) { summary in
                            evidenceCard(summary)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func evidenceCard(_ summary: TranslationEvidenceSummary) -> some View {
        let selected = model.selectedTranslationEvidenceID == summary.id
        let reviewStatus = summary.review?.status ?? .unreviewed
        let role = summary.manifest?.romRole.title ?? "Unreadable capture"
        let frame = summary.manifest.map { "frame \($0.frameNumber)" } ?? "unknown frame"
        let isBaseline = model.translationBaselines.contains {
            $0.isIntact && $0.baseline.evidenceName == summary.artifact.name
        }
        return Button {
            model.selectTranslationEvidence(summary.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let data = summary.framePNG, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(width: 184, height: 110)
                .background(.black, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                HStack {
                    Text(summary.manifest?.romRole.title ?? "Unreadable")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if model.translationBaselines.contains(where: {
                        $0.isIntact
                            && $0.baseline.evidenceName == summary.artifact.name
                    }) {
                        Image(systemName: "scope")
                            .foregroundStyle(.indigo)
                            .help("Approved regression baseline")
                    }
                    Image(systemName: evidenceReviewSymbol(reviewStatus))
                        .foregroundStyle(evidenceReviewColor(reviewStatus))
                        .help(reviewStatus.title)
                    Image(systemName: summary.isIntact ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(summary.isIntact ? Color.green : Color.orange)
                }
                Text(summary.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(width: 204, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .help(summary.integrityIssue ?? "Open this capture in the review desk")
        .accessibilityLabel("\(role), \(frame)")
        .accessibilityValue(
            "\(reviewStatus.title), \(summary.isIntact ? "integrity verified" : "integrity problem")\(isBaseline ? ", approved regression baseline" : "")"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button("Show in Finder", systemImage: "folder") {
                model.revealTranslationEvidence(summary)
            }
        }
    }

    @ViewBuilder
    private var evidenceReviewDesk: some View {
        if let evidence = model.selectedTranslationEvidence {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Evidence review")
                            .font(.title3.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Inspect the captured screen, record a verdict, and export only the safe diagnostic surface.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(
                        evidence.isIntact ? "Integrity verified" : "Integrity problem",
                        systemImage: evidence.isIntact ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(evidence.isIntact ? Color.green : Color.orange)
                }

                if let pair = model.pairedTranslationEvidence {
                    pairedEvidenceInspector(evidence, pair: pair)
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        reviewPreview(evidence, paired: false)
                            .frame(maxWidth: 610)
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Waiting for the opposite ROM", systemImage: "link.badge.plus")
                                .font(.headline)
                            Text("Capture the opposite ROM with this same route to unlock overlay, difference, and exact pixel zoom.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        evidenceMetadata(evidence)

                        if let issue = evidence.integrityIssue ?? evidence.reviewIssue {
                            Label(issue, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .frame(width: 285, alignment: .topLeading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(
                                "Verdict for \(evidence.manifest?.romRole.title ?? "selected capture")"
                            )
                                .font(.subheadline.weight(.semibold))
                            Picker("Verdict", selection: $model.translationEvidenceReviewStatus) {
                                ForEach(TranslationEvidenceReviewStatus.allCases) { status in
                                    Text(status.title).tag(status)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Review note")
                                .font(.subheadline.weight(.semibold))
                            TextEditor(text: $model.translationEvidenceReviewNote)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .frame(minHeight: 112)
                                .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(.separator.opacity(0.55))
                                }
                                .accessibilityLabel("Evidence review note")
                        }

                        HStack {
                            Button("Save Review", systemImage: "checkmark.circle.fill") {
                                model.saveTranslationEvidenceReview()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.translationEvidenceReviewHasChanges)

                            Button("Extract Source Text…", systemImage: "text.viewfinder") {
                                model.beginTranslationTextIntake()
                            }
                            .disabled(!model.canStartTranslationTextIntake)
                            .help("Recognize visible source text locally, then review every line")

                            Menu {
                                Button("Show Capture in Finder", systemImage: "folder") {
                                    model.revealTranslationEvidence(evidence)
                                }

                                Button("Export Source-Free Diagnostic…", systemImage: "shippingbox") {
                                    model.exportSelectedTranslationDiagnostic()
                                }
                                .disabled(!evidence.isIntact)

                                if model.selectedTranslationEvidenceHasTextIntake {
                                    Divider()
                                    Button("Show Saved Source Text", systemImage: "doc.text.magnifyingglass") {
                                        model.revealTranslationTextIntake()
                                    }
                                }
                            } label: {
                                Label("More", systemImage: "ellipsis.circle")
                            }

                            Spacer()
                        }

                        if evidence.manifest?.romRole == .patched,
                           evidence.manifest?.route != nil {
                            Divider()
                            regressionBaselinePanel(evidence)
                                .id("translation-baseline-controls")
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }

                Label(
                    "Diagnostic export includes frame, route, hashes, metadata, and review; ROM, RAM, state, and save bytes remain private.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func regressionBaselinePanel(
        _ evidence: TranslationEvidenceSummary
    ) -> some View {
        let baseline = model.selectedTranslationEvidenceBaseline
        let isCurrent = model.selectedTranslationEvidenceIsBaseline
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((isCurrent ? Color.green : Color.indigo).opacity(0.12))
                Image(systemName: isCurrent ? "scope" : "scope")
                    .foregroundStyle(isCurrent ? Color.green : Color.indigo)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(isCurrent ? "Approved regression baseline" : "Regression baseline")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(regressionBaselineDetail(evidence, baseline: baseline, isCurrent: isCurrent))
                    .font(.caption)
                    .foregroundStyle(
                        baseline?.integrityIssue == nil ? Color.secondary : Color.orange
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            if isCurrent {
                Button("Remove", systemImage: "xmark.circle") {
                    model.removeSelectedTranslationEvidenceBaseline()
                }
            } else {
                Button(
                    baseline == nil ? "Set Baseline" : "Replace Baseline",
                    systemImage: "scope"
                ) {
                    model.setSelectedTranslationEvidenceBaseline()
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(!model.selectedTranslationEvidenceCanBecomeBaseline)
                .help("Approve and save this patched evidence before setting it as the route baseline.")

                if baseline != nil {
                    Button("Remove", systemImage: "xmark.circle") {
                        model.removeSelectedTranslationEvidenceBaseline()
                    }
                }
            }
        }
        .padding(11)
        .background(Color.indigo.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func regressionBaselineDetail(
        _ evidence: TranslationEvidenceSummary,
        baseline: TranslationRouteBaselineSummary?,
        isCurrent: Bool
    ) -> String {
        if isCurrent {
            return "Future suite runs compare their patched endpoint with this exact approved frame."
        }
        if let issue = baseline?.integrityIssue {
            return issue
        }
        if evidence.review?.status != .approved || model.translationEvidenceReviewHasChanges {
            return "Choose Approved and save the review before promoting this frame."
        }
        if baseline != nil {
            return "Replace the existing baseline with this approved patched frame."
        }
        return "Use this approved frame to detect later visual changes on the same route."
    }

    private func pairedEvidenceInspector(
        _ evidence: TranslationEvidenceSummary,
        pair: TranslationEvidenceSummary
    ) -> some View {
        let original = evidence.manifest?.romRole == .original ? evidence : pair
        let patched = evidence.manifest?.romRole == .patched ? evidence : pair
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Exact-route pair", systemImage: "link.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Text("Matched by SHA-256")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Inspect RAM", systemImage: "memorychip") {
                    model.inspectSelectedTranslationRAM()
                }
                .disabled(!model.canInspectSelectedTranslationRAM)
                .help("Compare the private Original and Patched internal-RAM snapshots at this exact checkpoint")
                .accessibilityIdentifier("translation-inspect-checkpoint-ram")
                Picker("View", selection: $evidenceComparisonMode) {
                    ForEach(EvidenceComparisonMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 285)
            }

            if let comparison = model.translationEvidenceFrameComparison {
                evidenceComparisonCanvas(
                    original: original,
                    patched: patched,
                    comparison: comparison
                )

                HStack(spacing: 12) {
                    Picker("Zoom", selection: $evidenceComparisonZoom) {
                        Text("1×").tag(1.0)
                        Text("2×").tag(2.0)
                        Text("4×").tag(4.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)

                    if evidenceComparisonMode == .overlay {
                        Text("Original")
                            .font(.caption)
                            .foregroundStyle(.cyan)
                        Slider(value: $evidenceOverlayAmount, in: 0...1)
                        Text("Patched")
                            .font(.caption)
                            .foregroundStyle(.purple)
                    } else {
                        Spacer()
                        Label(
                            "\(comparison.width) × \(comparison.height) native pixels",
                            systemImage: "viewfinder"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                evidenceComparisonMetrics(comparison.visualization)
            } else {
                ContentUnavailableView {
                    Label("Comparison unavailable", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text(
                        model.translationEvidenceFrameComparisonIssue
                            ?? "The paired frames could not be decoded at matching dimensions."
                    )
                }
                .frame(maxWidth: .infinity, minHeight: 230)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func evidenceComparisonCanvas(
        original: TranslationEvidenceSummary,
        patched: TranslationEvidenceSummary,
        comparison: TranslationEvidenceFrameComparison
    ) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Group {
                switch evidenceComparisonMode {
                case .sideBySide:
                    HStack(alignment: .top, spacing: 14) {
                        evidencePixelPanel(
                            title: "Original",
                            frame: original.manifest?.frameNumber,
                            data: original.framePNG,
                            comparison: comparison,
                            color: .cyan
                        )
                        evidencePixelPanel(
                            title: "Patched",
                            frame: patched.manifest?.frameNumber,
                            data: patched.framePNG,
                            comparison: comparison,
                            color: .purple
                        )
                    }
                case .overlay:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Original")
                                .foregroundStyle(.cyan)
                            Text("↔")
                                .foregroundStyle(.secondary)
                            Text("Patched")
                                .foregroundStyle(.purple)
                        }
                        .font(.caption.monospaced().weight(.semibold))
                        ZStack {
                            evidencePixelImage(
                                original.framePNG,
                                comparison: comparison
                            )
                            evidencePixelImage(
                                patched.framePNG,
                                comparison: comparison
                            )
                            .opacity(evidenceOverlayAmount)
                        }
                    }
                case .difference:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.orange, .pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 9, height: 9)
                            Text("Changed pixels · brighter color means larger channel delta")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        evidencePixelImage(
                            comparison.heatmapPNG,
                            comparison: comparison
                        )
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 380)
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func evidencePixelPanel(
        title: String,
        frame: UInt64?,
        data: Data?,
        comparison: TranslationEvidenceFrameComparison,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .foregroundStyle(color)
                if let frame {
                    Text("Frame \(frame)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.monospaced().weight(.semibold))
            evidencePixelImage(data, comparison: comparison)
        }
    }

    @ViewBuilder
    private func evidencePixelImage(
        _ data: Data?,
        comparison: TranslationEvidenceFrameComparison
    ) -> some View {
        let width = CGFloat(comparison.width) * evidenceComparisonZoom
        let height = CGFloat(comparison.height) * evidenceComparisonZoom
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: width, height: height)
                .background(.black)
                .overlay {
                    Rectangle()
                        .stroke(.white.opacity(0.12))
                }
        } else {
            ContentUnavailableView("Frame unavailable", systemImage: "photo.badge.exclamationmark")
                .frame(width: width, height: height)
        }
    }

    private func evidenceComparisonMetrics(
        _ visualization: RGBFrameVisualization
    ) -> some View {
        let difference = visualization.difference
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                comparisonMetric(
                    "\(difference.differentPixelFraction.formatted(.percent.precision(.fractionLength(2))))",
                    label: "Pixels changed"
                )
                comparisonMetric(
                    "\(difference.differentPixelCount) / \(difference.pixelCount)",
                    label: "Changed pixels"
                )
                comparisonMetric(
                    difference.meanAbsoluteChannelError.formatted(
                        .number.precision(.fractionLength(2))
                    ),
                    label: "Mean delta"
                )
                comparisonMetric(
                    "\(difference.maximumChannelError)",
                    label: "Largest delta"
                )
            }
            if let bounds = visualization.changedBounds {
                Label(
                    "Change bounds: x \(bounds.x), y \(bounds.y), \(bounds.width) × \(bounds.height) pixels",
                    systemImage: "viewfinder.rectangular"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                Label("The paired frames are pixel-identical.", systemImage: "equal.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private func comparisonMetric(
        _ value: String,
        label: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func reviewPreview(
        _ evidence: TranslationEvidenceSummary,
        paired: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(evidence.manifest?.romRole.title ?? "Unreadable")
                    .font(.headline)
                if paired {
                    Text("PAIRED")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.green)
                }
                Spacer()
                if let frame = evidence.manifest?.frameNumber {
                    Text("Frame \(frame)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Group {
                if let data = evidence.framePNG, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                } else {
                    ContentUnavailableView("Preview unavailable", systemImage: "photo.badge.exclamationmark")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 188, maxHeight: 230)
            .background(.black, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func evidenceMetadata(_ evidence: TranslationEvidenceSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let manifest = evidence.manifest {
                LabeledContent("Capture", value: manifest.romRole.title)
                LabeledContent("Created", value: manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Frame", value: "\(manifest.frameNumber)")
                LabeledContent("Backend", value: manifest.backend)
                LabeledContent("Route", value: manifest.route == nil ? "Not recorded" : "Digest verified")
            } else {
                Text("The capture manifest could not be read.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
    }

    private var evidenceHistorySubtitle: String {
        let approved = model.translationEvidence.filter { $0.review?.status == .approved }.count
        let needsWork = model.translationEvidence.filter { $0.review?.status == .needsWork }.count
        if approved == 0 && needsWork == 0 {
            return "Select a native capture to review it, pair it, or export a safe diagnostic."
        }
        return "\(approved) approved · \(needsWork) need work · route and artifact integrity checked."
    }

    private func historySection<Content: View>(
        title: String,
        subtitle: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
            content()
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func testLoop(_ project: TranslationProject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Deterministic Route Testing")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .background(
                        TranslationLabOverviewElementGeometryReader(
                            identifier: TranslationLabOverviewAccessibility.workflow,
                            probe: overviewGeometryProbe
                        )
                    )
                Text("Start Original from a clean boot, save one exact checkpoint, then replay it against both builds for native-pixel review.")
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                labStep(
                    number: "1",
                    title: "Clean Boot",
                    detail: "Boot with clean, isolated persistence.",
                    symbol: "1.circle.fill",
                    accent: .blue
                )
                labStep(
                    number: "2",
                    title: "Record",
                    detail: latestRouteDetail,
                    symbol: model.latestTranslationRoute == nil ? "record.circle" : "checkmark.circle.fill",
                    accent: model.latestTranslationRoute == nil ? .orange : .green
                )
                labStep(
                    number: "3",
                    title: "Replay Both",
                    detail: "Strict pack, then deterministic replay.",
                    symbol: "hammer.circle.fill",
                    accent: .purple
                )
                labStep(
                    number: "4",
                    title: "Review",
                    detail: model.lastTranslationEvidenceURL == nil
                        ? "Frame + RAM + state + manifest."
                        : "Latest evidence is ready in the project.",
                    symbol: model.lastTranslationEvidenceURL == nil ? "camera.metering.center.weighted" : "checkmark.seal.fill",
                    accent: model.lastTranslationEvidenceURL == nil ? .cyan : .green
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(TranslationLabOverviewAccessibility.workflowLabel)
            .accessibilityIdentifier(TranslationLabOverviewAccessibility.workflow)

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    routeVerificationSummary
                        .frame(minWidth: 280, alignment: .leading)
                    Spacer(minLength: 16)
                    routeVerificationActions
                }

                VStack(alignment: .leading, spacing: 14) {
                    routeVerificationSummary
                    routeVerificationActions
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.cyan.opacity(0.28), .purple.opacity(0.28)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(TranslationLabOverviewAccessibility.currentActionLabel)
            .accessibilityIdentifier(TranslationLabOverviewAccessibility.currentAction)
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var routeVerificationSummary: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.18), .purple.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("Automated A/B route verification")
                    .font(.headline)
                Text(routeVerificationDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var routeVerificationActions: some View {
        if model.translationComparisonPhase == .preparing {
            VStack(alignment: .trailing, spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(model.translationComparisonPhase?.title ?? "Preparing")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        } else if model.latestTranslationRoute == nil {
            Button("Record New Test…", systemImage: "record.circle") {
                model.startCleanBootTranslationTest()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                !model.engineCanExecute
                    || !model.translationOriginalROMAvailable
                    || model.translationToolIsRunning
                    || model.isPlaying
            )
            .accessibilityIdentifier(TranslationLabOverviewAccessibility.recordTest)
            .background(
                TranslationLabOverviewElementGeometryReader(
                    identifier: TranslationLabOverviewAccessibility.recordTest,
                    probe: overviewGeometryProbe
                )
            )
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) {
                    findFirstChangeButton
                    verifyLatestRouteButton
                }
                VStack(alignment: .trailing, spacing: 9) {
                    findFirstChangeButton
                    verifyLatestRouteButton
                }
            }
        }
    }

    private var findFirstChangeButton: some View {
        Button("Find First Change", systemImage: "scope") {
            model.locateFirstTranslationVisualChange()
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!model.canLocateFirstTranslationVisualChange)
        .help(
            "Replay Original and Patched from the same clean boot and inputs, then locate their first changed game-raster frame"
        )
        .accessibilityIdentifier(TranslationLabOverviewAccessibility.findFirstChange)
        .background(
            TranslationLabOverviewElementGeometryReader(
                identifier: TranslationLabOverviewAccessibility.findFirstChange,
                probe: overviewGeometryProbe
            )
        )
    }

    private var verifyLatestRouteButton: some View {
        Button("Verify Original vs Patched", systemImage: "checkmark.arrow.trianglehead.counterclockwise") {
            translationLabPageRaw = TranslationLabPage.evidence.rawValue
            model.verifyLatestTranslationRoute()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!model.canVerifyLatestTranslationRoute)
        .help(routeVerificationHelp)
        .accessibilityIdentifier(TranslationLabOverviewAccessibility.verifyRoute)
        .background(
            TranslationLabOverviewElementGeometryReader(
                identifier: TranslationLabOverviewAccessibility.verifyRoute,
                probe: overviewGeometryProbe
            )
        )
    }

    private var routeVerificationDetail: String {
        if model.latestTranslationRoute == nil {
            return "Record a clean-boot test once; SwanSong will then run the exact same frames against both ROMs."
        }
        return "Runs guarded QA and strict pack, replays the selected route against Original and Patched, captures both endpoints, and opens the paired review."
    }

    private var routeVerificationHelp: String {
        if !model.engineCanExecute {
            return "Build and load the live ares engine first."
        }
        if !model.translationOriginalROMAvailable {
            return "The project’s original ROM is missing."
        }
        if model.latestTranslationRoute == nil {
            return "Record or select an input route first."
        }
        if let issue = model.selectedTranslationRouteProofIssue {
            return issue
        }
        return "Verify this route against both ROMs with isolated persistence and exact evidence."
    }

    private var safeguards: some View {
        HStack(alignment: .top, spacing: 14) {
            safeguard(
                symbol: "lock.shield.fill",
                title: "Private by construction",
                detail: "ROMs, script text, tables, states, RAM, and screenshots stay under the linked project."
            )
            safeguard(
                symbol: "externaldrive.badge.checkmark",
                title: "Isolated test saves",
                detail: "Translation runs never read or overwrite the normal game library’s cartridge data."
            )
            safeguard(
                symbol: "terminal.fill",
                title: "Guarded toolkit bridge",
                detail: "Only Status, QA, Validate, Strict Pack, and Capture Intake can run—never project-defined hooks."
            )
        }
    }

    private var toolkitRunningStatus: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.translationToolPhase ?? "Running toolkit stage…")
                    .font(.headline)
                Text("The source ROM remains untouched while the guarded command runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("In progress")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.blue.opacity(0.11), in: Capsule())
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var toolkitOutput: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Toolkit Output")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Selectable output from SwanSong’s allowlisted project commands.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Read only")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView([.horizontal, .vertical]) {
                Text(model.translationCommandOutput)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 340, maxHeight: 620)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var readinessBadge: some View {
        let status = model.translationReadiness?.status ?? .unknown
        return Text(status.rawValue)
            .font(.caption2.monospaced().weight(.bold))
            .foregroundStyle(readinessColor(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(readinessColor(status).opacity(0.12), in: Capsule())
            .help(model.translationReadiness?.headline ?? "Refresh to check project readiness")
    }

    private var latestRouteDetail: String {
        guard let route = model.latestTranslationRoute else {
            return "Capture input timing from a visible route."
        }
        switch route.proofEligibility {
        case .legacyStartUnknown:
            return "v1 route · Re-record from clean boot."
        case .rtcStartUnknown:
            return "v2 route · Re-record with fixed UTC RTC."
        default:
            break
        }
        return "Target frame \(route.targetFrameNumber ?? route.totalFrames) · \(route.events.count) input changes."
    }

    private func labStep(
        number: String,
        title: String,
        detail: String,
        symbol: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(number). \(title)")
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.18))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(TranslationLabOverviewAccessibility.workflowStep(number))
    }

    private func safeguard(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func readinessColor(_ status: TranslationReadinessStatus) -> Color {
        switch status {
        case .complete: .green
        case .pending: .orange
        case .blocked: .red
        case .unknown: .secondary
        }
    }

    private func readinessSymbol(_ status: TranslationReadinessStatus) -> String {
        switch status {
        case .complete: "checkmark.circle.fill"
        case .pending: "clock.fill"
        case .blocked: "exclamationmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private func actionPriorityColor(_ priority: TranslationActionPriority) -> Color {
        switch priority {
        case .high: .red
        case .medium: .orange
        case .low: .blue
        case .unknown: .secondary
        }
    }

    private func evidenceReviewColor(_ status: TranslationEvidenceReviewStatus) -> Color {
        switch status {
        case .unreviewed: .secondary
        case .approved: .green
        case .needsWork: .orange
        }
    }

    private func evidenceReviewSymbol(_ status: TranslationEvidenceReviewStatus) -> String {
        switch status {
        case .unreviewed: "circle.dashed"
        case .approved: "checkmark.circle.fill"
        case .needsWork: "exclamationmark.bubble.fill"
        }
    }
}

enum TranslationTextIntakeSelectionGeometry {
    static func imageRect(container: CGSize, pixels: CGSize) -> CGRect {
        guard container.width > 0,
              container.height > 0,
              pixels.width > 0,
              pixels.height > 0 else { return .zero }
        let scale = min(container.width / pixels.width, container.height / pixels.height)
        let size = CGSize(width: pixels.width * scale, height: pixels.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func viewRect(
        for selection: TranslationPixelRect,
        imageRect: CGRect,
        pixels: CGSize
    ) -> CGRect? {
        guard imageRect.width > 0, imageRect.height > 0,
              pixels.width > 0, pixels.height > 0,
              selection.isValid else { return nil }
        let scaleX = imageRect.width / pixels.width
        let scaleY = imageRect.height / pixels.height
        return CGRect(
            x: imageRect.minX + CGFloat(selection.x) * scaleX,
            y: imageRect.minY + CGFloat(selection.y) * scaleY,
            width: CGFloat(selection.width) * scaleX,
            height: CGFloat(selection.height) * scaleY
        ).intersection(imageRect)
    }

    static func pixelRect(
        for dragRect: CGRect,
        imageRect: CGRect,
        pixels: CGSize
    ) -> TranslationPixelRect? {
        guard imageRect.width > 0, imageRect.height > 0,
              pixels.width > 0, pixels.height > 0 else { return nil }
        let clipped = dragRect.standardized.intersection(imageRect)
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else { return nil }

        let minX = Int(
            (((clipped.minX - imageRect.minX) / imageRect.width) * pixels.width)
                .rounded(.down)
        )
        let minY = Int(
            (((clipped.minY - imageRect.minY) / imageRect.height) * pixels.height)
                .rounded(.down)
        )
        let maxX = Int(
            (((clipped.maxX - imageRect.minX) / imageRect.width) * pixels.width)
                .rounded(.up)
        )
        let maxY = Int(
            (((clipped.maxY - imageRect.minY) / imageRect.height) * pixels.height)
                .rounded(.up)
        )
        let pixelWidth = Int(pixels.width)
        let pixelHeight = Int(pixels.height)
        let x = min(max(minX, 0), pixelWidth)
        let y = min(max(minY, 0), pixelHeight)
        let boundedMaxX = min(max(maxX, x), pixelWidth)
        let boundedMaxY = min(max(maxY, y), pixelHeight)
        let result = TranslationPixelRect(
            x: x,
            y: y,
            width: boundedMaxX - x,
            height: boundedMaxY - y
        )
        return result.isValid ? result : nil
    }
}

struct TranslationTextIntakeView: View {
    static let accessibilityIdentifier = "translation-text-intake-sheet"

    @Bindable var model: AppModel
    @FocusState private var focusedLineID: String?
    @FocusState private var manualFieldIsFocused: Bool

    private var hasReviewSession: Bool {
        model.translationTextIntakeSession != nil
    }

    private var canChooseRegion: Bool {
        !model.translationTextIntakeIsRecognizing && !hasReviewSession
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 900, idealWidth: 980, minHeight: 650, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(SwanTheme.accent)
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    private var header: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SwanTheme.accent, SwanTheme.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("Capture to Source Text")
                    .font(.title2.weight(.semibold))
                Text("Select visible dialogue, recognize it on this Mac, then verify every line.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("On-device only", systemImage: "lock.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1), in: Capsule())

            Button("Close", systemImage: "xmark") {
                model.dismissTranslationTextIntake()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .disabled(model.translationTextIntakeIsRecognizing)
            .help("Close source-text intake")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 17)
    }

    @ViewBuilder
    private var content: some View {
        if let data = model.selectedTranslationEvidence?.framePNG,
           let image = NSImage(data: data),
           let pixels = model.translationTextIntakeImagePixelSize,
           let selection = model.translationTextIntakeSelection {
            HStack(alignment: .top, spacing: 22) {
                captureDesk(image: image, pixels: pixels, selection: selection)
                    .frame(maxWidth: .infinity)

                Divider()

                reviewDesk
                    .frame(width: 350)
            }
            .padding(22)
        } else {
            ContentUnavailableView {
                Label("Capture Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Close this window and select an intact evidence capture.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func captureDesk(
        image: NSImage,
        pixels: CGSize,
        selection: TranslationPixelRect
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("1. Select a text region")
                        .font(.headline)
                    Text(canChooseRegion ? "Drag over the dialogue you want to transcribe." : "Region locked while you review this result.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(selection.width) × \(selection.height) px")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            TranslationCaptureSelectionView(
                image: image,
                pixelSize: pixels,
                selection: selection,
                isEnabled: canChooseRegion,
                onSelection: model.updateTranslationTextIntakeSelection
            )
            .frame(minHeight: 350, maxHeight: 440)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    regionButtons
                    Spacer()
                    regionCoordinateLabel(selection)
                }
                VStack(alignment: .leading, spacing: 8) {
                    regionButtons
                    regionCoordinateLabel(selection)
                }
            }

            Label(
                "The saved intake contains reviewed text, bounds, confidence, and a capture hash—never image pixels, ROM bytes, paths, or cloud requests.",
                systemImage: "hand.raised.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var regionButtons: some View {
        if canChooseRegion {
            HStack(spacing: 8) {
                Button("Full Frame") {
                    model.useFullFrameForTranslationTextIntake()
                }
                Button("Dialogue Band") {
                    model.useDialogueBandForTranslationTextIntake()
                }
            }
            .controlSize(.small)
        } else if !model.translationTextIntakeIsRecognizing {
            Button("Change Region", systemImage: "crop") {
                model.restartTranslationTextIntakeRegionSelection()
            }
            .controlSize(.small)
        }
    }

    private func regionCoordinateLabel(_ selection: TranslationPixelRect) -> some View {
        Text("x \(selection.x) · y \(selection.y)")
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
    }

    private var reviewDesk: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("2. Recognize locally")
                        .font(.headline)
                    Text("Apple Vision runs locally; only lines fully inside this region are kept. No translation is guessed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    model.recognizeTranslationTextIntake()
                } label: {
                    if model.translationTextIntakeIsRecognizing {
                        Label("Recognizing…", systemImage: "ellipsis")
                    } else {
                        Label(hasReviewSession ? "Recognize Again" : "Recognize Text", systemImage: "viewfinder")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.translationTextIntakeIsRecognizing || hasReviewSession)
                .frame(maxWidth: .infinity, alignment: .leading)

                if model.translationTextIntakeIsRecognizing {
                    ProgressView("Analyzing selected region…")
                        .controlSize(.small)
                }

                if let issue = model.translationTextIntakeIssue {
                    Label(issue, systemImage: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Text("3. Review source lines")
                        .font(.headline)
                    Text("Correct OCR mistakes, then confirm the text you can actually see.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.translationTextIntakeLines.isEmpty {
                    Text("Recognized lines will appear here. You can also type a visible line manually.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.translationTextIntakeLines) { line in
                            sourceLineEditor(line)
                        }
                    }
                }

                manualLineEntry
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }

    private func sourceLineEditor(_ line: TranslationTextIntakeLine) -> some View {
        let isConfirmed = line.reviewStatus == .confirmed
        let confidence = line.confidence.map {
            "\(Int(($0.value * 100).rounded()))%"
        } ?? "Manual"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    isConfirmed ? "Confirmed" : confidence,
                    systemImage: isConfirmed ? "checkmark.circle.fill" : "waveform.badge.magnifyingglass"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isConfirmed ? Color.green : Color.secondary)
                Spacer()
                Text("\(line.bounds.width) × \(line.bounds.height)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            TextField(
                "Visible source text",
                text: Binding(
                    get: {
                        model.translationTextIntakeDrafts[line.id]
                            ?? line.reviewedText
                    },
                    set: { model.updateTranslationTextIntakeDraft(id: line.id, text: $0) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
            .focused($focusedLineID, equals: line.id)
            .disabled(isConfirmed)
            .accessibilityLabel("Source text \(line.id)")

            HStack {
                if isConfirmed {
                    Button("Edit", systemImage: "pencil") {
                        model.reopenTranslationTextIntakeLine(line.id)
                        focusedLineID = line.id
                    }
                } else {
                    Button("Confirm Line", systemImage: "checkmark") {
                        model.confirmTranslationTextIntakeLine(line.id)
                    }
                }
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(11)
        .background(
            (isConfirmed ? Color.green : Color.accentColor).opacity(0.055),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke((isConfirmed ? Color.green : Color.accentColor).opacity(0.16))
        }
    }

    private var manualLineEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual source line")
                .font(.subheadline.weight(.semibold))
            TextField(
                "Type only text visible in the selected region",
                text: $model.translationTextIntakeManualDraft,
                axis: .vertical
            )
            .lineLimit(1...3)
            .focused($manualFieldIsFocused)
            HStack {
                Spacer()
                Button("Add Line", systemImage: "plus") {
                    model.addManualTranslationTextIntakeLine()
                    manualFieldIsFocused = true
                }
                .disabled(
                    model.translationTextIntakeManualDraft
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                        || model.translationTextIntakeIsRecognizing
                )
            }
        }
        .padding(11)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Cancel", role: .cancel) {
                model.dismissTranslationTextIntake()
            }
            .disabled(model.translationTextIntakeIsRecognizing)

            if model.translationTextIntakeHasSavedArtifact {
                Button("Show Existing Intake", systemImage: "doc.text.magnifyingglass") {
                    model.revealTranslationTextIntake()
                }
            }

            Spacer()

            Button("Confirm All") {
                model.confirmAllTranslationTextIntakeLines()
            }
            .disabled(model.translationTextIntakeLines.isEmpty)

            Button("Confirm & Save Intake", systemImage: "checkmark.shield.fill") {
                model.saveTranslationTextIntake()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.translationTextIntakeCanSave)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }
}

private struct TranslationCaptureSelectionView: View {
    let image: NSImage
    let pixelSize: CGSize
    let selection: TranslationPixelRect
    let isEnabled: Bool
    let onSelection: (TranslationPixelRect) -> Void

    @State private var dragRect: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let imageRect = TranslationTextIntakeSelectionGeometry.imageRect(
                container: proxy.size,
                pixels: pixelSize
            )
            let selectedRect = dragRect
                ?? TranslationTextIntakeSelectionGeometry.viewRect(
                    for: selection,
                    imageRect: imageRect,
                    pixels: pixelSize
                )
                ?? imageRect

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.94))

                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                Path { path in
                    path.addRect(imageRect)
                    path.addRect(selectedRect.intersection(imageRect))
                }
                .fill(
                    Color.black.opacity(isEnabled ? 0.46 : 0.30),
                    style: FillStyle(eoFill: true)
                )

                Rectangle()
                    .stroke(Color.white.opacity(0.94), lineWidth: 1)
                    .background(Color.accentColor.opacity(0.09))
                    .frame(width: selectedRect.width, height: selectedRect.height)
                    .position(x: selectedRect.midX, y: selectedRect.midY)

                ForEach(0..<4, id: \.self) { corner in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .position(cornerPoint(corner, rect: selectedRect))
                        .shadow(color: .black.opacity(0.4), radius: 1)
                }

                if isEnabled {
                    Label("Drag to select", systemImage: "viewfinder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.62), in: Capsule())
                        .position(x: imageRect.midX, y: imageRect.maxY - 18)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard isEnabled else { return }
                        dragRect = CGRect(
                            x: value.startLocation.x,
                            y: value.startLocation.y,
                            width: value.location.x - value.startLocation.x,
                            height: value.location.y - value.startLocation.y
                        )
                        .standardized
                        .intersection(imageRect)
                    }
                    .onEnded { value in
                        guard isEnabled else {
                            dragRect = nil
                            return
                        }
                        let rect = CGRect(
                            x: value.startLocation.x,
                            y: value.startLocation.y,
                            width: value.location.x - value.startLocation.x,
                            height: value.location.y - value.startLocation.y
                        )
                        if let pixels = TranslationTextIntakeSelectionGeometry.pixelRect(
                            for: rect,
                            imageRect: imageRect,
                            pixels: pixelSize
                        ) {
                            onSelection(pixels)
                        }
                        dragRect = nil
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Captured frame text region")
            .accessibilityValue(
                "x \(selection.x), y \(selection.y), width \(selection.width), height \(selection.height) pixels"
            )
            .accessibilityHint("Use Full Frame or Dialogue Band for keyboard-accessible region presets")
        }
    }

    private func cornerPoint(_ corner: Int, rect: CGRect) -> CGPoint {
        switch corner {
        case 0: CGPoint(x: rect.minX, y: rect.minY)
        case 1: CGPoint(x: rect.maxX, y: rect.minY)
        case 2: CGPoint(x: rect.minX, y: rect.maxY)
        default: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

enum GameConfidenceAccessibility {
    static let panel = "game-confidence-panel"
    static let launchReadiness = "game-confidence-launch-readiness"
    static let compatibilityEvidence = "game-confidence-evidence"
    static let romIntegrity = "game-confidence-rom-integrity"
    static let verdictControls = "game-confidence-verdict-controls"
    static let verdictWorks = "game-confidence-verdict-works"
    static let verdictIssues = "game-confidence-verdict-issues"
    static let verdictClear = "game-confidence-verdict-clear"
    static let note = "game-confidence-note"
    static let saveNote = "game-confidence-save-note"

    static func card(_ id: GameRecord.ID) -> String {
        "game-confidence-card-\(id.uuidString.lowercased())"
    }

    static func cardPrimaryAction(_ id: GameRecord.ID) -> String {
        "game-card-primary-action-\(id.uuidString.lowercased())"
    }
}

enum GameInspectorAccessibility {
    static let systemIdentity = "game-inspector-system-identity"
    static let runtimeStatus = "game-inspector-runtime-status"
    static let confidenceExplanations = "game-inspector-confidence-explanations"
    static let gameDetails = "game-inspector-game-details"
    static let pocketSave = "game-inspector-pocket-save"
    static let pocketChallengeProgramFlash = "pocket-challenge-v2-program-flash"
}

enum SettingsSurfaceAccessibility {
    static let minimumInteractiveDimension: CGFloat = 28
    static let startupFiles = "startup-files-settings"
    static let controllerMapping = "controller-mapping-settings"
    static let controllerLiveInput = "controller-live-input-disclosure"
}

@MainActor
final class GameConfidenceGeometryProbe {
    static let coordinateSpace = "game-confidence-scroll-viewport"

    private(set) var viewportFrame = CGRect.zero
    private(set) var actionFrames: [String: CGRect] = [:]

    func recordViewport(_ frame: CGRect) {
        viewportFrame = frame
    }

    func recordAction(identifier: String, frame: CGRect) {
        actionFrames[identifier] = frame
    }
}

private struct GameConfidenceViewportGeometryReader: View {
    let probe: GameConfidenceGeometryProbe?

    var body: some View {
        GeometryReader { proxy in
            let frame = CGRect(origin: .zero, size: proxy.size)
            Color.clear
                .onAppear { probe?.recordViewport(frame) }
                .onChange(of: frame) { _, value in probe?.recordViewport(value) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct GameConfidenceActionGeometryReader: View {
    let identifier: String
    let probe: GameConfidenceGeometryProbe?

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(
                in: .named(GameConfidenceGeometryProbe.coordinateSpace)
            )
            Color.clear
                .onAppear { probe?.recordAction(identifier: identifier, frame: frame) }
                .onChange(of: frame) { _, value in
                    probe?.recordAction(identifier: identifier, frame: value)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension GameCompatibilityStatus {
    var confidenceTitle: String {
        switch self {
        case .untested: "Untested"
        case .reachedVideo: "Reached video"
        case .confirmedWorks: "Works"
        case .reportedIssues: "Issues"
        }
    }

    var confidenceSymbol: String {
        switch self {
        case .untested: "questionmark.circle"
        case .reachedVideo: "display"
        case .confirmedWorks: "checkmark.seal.fill"
        case .reportedIssues: "exclamationmark.bubble.fill"
        }
    }

    var confidenceColor: Color {
        switch self {
        case .untested: .secondary
        case .reachedVideo: SwanTheme.cyan
        case .confirmedWorks: .green
        case .reportedIssues: .orange
        }
    }
}

private struct GameCompatibilityBadge: View {
    let status: GameCompatibilityStatus

    var body: some View {
        Label("Compatibility: \(status.confidenceTitle)", systemImage: status.confidenceSymbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.confidenceColor)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(status.confidenceColor.opacity(0.10), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(status.confidenceColor.opacity(0.22), lineWidth: 0.75)
            }
            .accessibilityLabel("Compatibility evidence: \(status.confidenceTitle)")
    }
}

private struct GameCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let game: GameRecord
    let artwork: GameArtworkRecord?
    let confidence: GameConfidence
    let isSelected: Bool
    let canPlay: Bool
    let managedHealth: ManagedGameHealth?
    let isCheckingManagedCopy: Bool
    let isRepairingManagedCopy: Bool
    let requiredFirmware: WonderSwanFirmwareKind?
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onRepair: () -> Void
    let onReAdd: () -> Void
    let onInstallFirmware: () -> Void
    let onFavorite: () -> Void
    let onUseProceduralArtwork: () -> Void
    let onCaptureArtworkNextPlay: () -> Void
    let canReveal: Bool
    let onReveal: () -> Void
    let onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardSelectionButton
            cardOverlayControls
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
        )
        .scaleEffect(isHovering && !reduceMotion ? 1.018 : 1)
        .shadow(
            color: .black.opacity(isHovering ? 0.16 : 0.06),
            radius: isHovering ? 18 : 7,
            y: isHovering ? 9 : 3
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isSelected)
        .onHover { isHovering = $0 }
        .contextMenu {
            if isRepairingManagedCopy {
                Button("Repairing…", systemImage: "wrench.and.screwdriver.fill") {}
                    .disabled(true)
            } else if isCheckingManagedCopy {
                Button("Checking Private Copy…", systemImage: "checkmark.shield") {}
                    .disabled(true)
            } else if managedHealth == .invalidReference {
                Button("Re-add Game…", systemImage: "plus.rectangle.on.folder", action: onReAdd)
            } else if needsRepair {
                Button("Repair Private Copy…", systemImage: "wrench.and.screwdriver.fill", action: onRepair)
            } else if let requiredFirmware {
                Button("Set Up \(requiredFirmware.title) & Play…", systemImage: "cpu", action: onInstallFirmware)
            } else {
                Button("Play", systemImage: "play.fill", action: onPlay)
                    .disabled(!canPlay)
            }
            Divider()
            Button(game.isFavorite ? "Remove from Favorites" : "Add to Favorites", action: onFavorite)
            if artwork != nil {
                Button("Use Procedural Artwork", systemImage: "rectangle.dashed", action: onUseProceduralArtwork)
            } else {
                Button("Capture Artwork Next Time Played", systemImage: "camera", action: onCaptureArtworkNextPlay)
            }
            if canReveal {
                Button(game.managedROM == nil ? "Show in Finder" : "Show Managed Copy in Finder", systemImage: "folder", action: onReveal)
            }
            Divider()
            Button("Remove from Library", role: .destructive, action: onRemove)
        }
    }

    private var cardSelectionButton: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                GameArtworkTile(game: game, artwork: artwork)
                    .aspectRatio(1.35, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(game.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(sourceDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(sourceHelp)
                    if let readinessStatus {
                        Label(readinessStatus.title, systemImage: readinessStatus.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(readinessStatus.color)
                            .padding(.top, 3)
                    }
                    GameCompatibilityBadge(status: confidence.compatibility)
                        .padding(.top, readinessStatus == nil ? 3 : 1)
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { performPrimaryAction() }
        )
        .accessibilityHint(accessibilityHint)
        .accessibilityLabel(game.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: accessibilityActionTitle) {
            performPrimaryAction()
        }
        .accessibilityIdentifier(GameConfidenceAccessibility.card(game.id))
    }

    private var cardOverlayControls: some View {
        HStack(spacing: 6) {
            if isSelected || isHovering {
                Button(action: performPrimaryAction) {
                    Label(cardPrimaryActionTitle, systemImage: cardPrimaryActionSymbol)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(SwanTheme.accent)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
                .disabled(cardPrimaryActionIsDisabled)
                .help(cardPrimaryActionHelp)
                .accessibilityIdentifier(
                    GameConfidenceAccessibility.cardPrimaryAction(game.id)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            Button(action: onFavorite) {
                Image(systemName: game.isFavorite ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(game.isFavorite ? .yellow : .white)
                    .frame(width: 28, height: 28)
                    .background(.black.opacity(0.32), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(game.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel(game.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
        .padding(.top, 21)
        .padding(.trailing, 21)
    }

    private var accessibilityHint: String {
        if isRepairingManagedCopy {
            return "The private copy is being repaired."
        }
        if isCheckingManagedCopy {
            return "The private copy is being verified."
        }
        if needsRepair {
            return "Select this game, then use Repair to choose the exact original game file."
        }
        if managedHealth == .invalidReference {
            return "This entry cannot be verified. Re-add the original game as a new library entry."
        }
        if let requiredFirmware {
            return "Select this game, then use the Set Up and Play action to choose the required \(requiredFirmware.title) startup file and continue."
        }
        return canPlay
            ? "Select this game. Double-click to play."
            : "Select this game. The native emulation engine is unavailable."
    }

    private var accessibilityValue: String {
        let system = game.systemTitle
        let artworkDescription = artwork == nil ? "procedural artwork" : "captured gameplay artwork"
        let compatibility = "compatibility evidence: \(confidence.compatibility.confidenceTitle)"
        if isRepairingManagedCopy {
            return "\(system); \(artworkDescription); repairing private copy; \(compatibility)"
        }
        if isCheckingManagedCopy {
            return "\(system); \(artworkDescription); checking private copy; \(compatibility)"
        }
        if managedHealth == .missing {
            return "\(system); \(artworkDescription); private copy missing; repair needed; \(compatibility)"
        }
        if managedHealth == .changed {
            return "\(system); \(artworkDescription); private copy changed; repair needed; \(compatibility)"
        }
        if managedHealth == .invalidReference {
            return "\(system); \(artworkDescription); library identity invalid; re-add needed; \(compatibility)"
        }
        if let requiredFirmware {
            return "\(system); \(artworkDescription); \(requiredFirmware.title) startup file setup needed; \(compatibility)"
        }
        return canPlay
            ? "\(system); \(artworkDescription); ready to play; \(compatibility)"
            : "\(system); \(artworkDescription); engine unavailable; \(compatibility)"
    }

    private var sourceDetail: String {
        let system = game.systemTitle
        return game.managedROM == nil ? system : "\(system) · Managed copy"
    }

    private var sourceHelp: String {
        guard let sourceFileName = game.sourceFileName else {
            return sourceDetail
        }
        return "Imported from \(sourceFileName)"
    }

    private var needsRepair: Bool {
        managedHealth == .missing || managedHealth == .changed
    }

    private var accessibilityActionTitle: String {
        if managedHealth == .invalidReference { return "Re-add Game" }
        if needsRepair { return "Repair" }
        return requiredFirmware == nil ? "Play" : "Set Up and Play"
    }

    private func performPrimaryAction() {
        if isRepairingManagedCopy || isCheckingManagedCopy {
            return
        } else if managedHealth == .invalidReference {
            onReAdd()
        } else if needsRepair {
            onRepair()
        } else if requiredFirmware == nil {
            onPlay()
        } else {
            onInstallFirmware()
        }
    }

    private var cardPrimaryActionTitle: String {
        if isRepairingManagedCopy { return "Repairing" }
        if isCheckingManagedCopy { return "Checking" }
        if managedHealth == .invalidReference { return "Re-add" }
        if needsRepair { return "Repair" }
        if requiredFirmware != nil { return "Set Up" }
        return "Play"
    }

    private var cardPrimaryActionSymbol: String {
        if isRepairingManagedCopy { return "wrench.and.screwdriver.fill" }
        if isCheckingManagedCopy { return "checkmark.shield" }
        if managedHealth == .invalidReference { return "plus.rectangle.on.folder" }
        if needsRepair { return "wrench.and.screwdriver.fill" }
        if requiredFirmware != nil { return "cpu" }
        return "play.fill"
    }

    private var cardPrimaryActionIsDisabled: Bool {
        isRepairingManagedCopy
            || isCheckingManagedCopy
            || (managedHealth != .invalidReference
                && !needsRepair
                && requiredFirmware == nil
                && !canPlay)
    }

    private var cardPrimaryActionHelp: String {
        if isRepairingManagedCopy { return "Repairing the private game copy" }
        if isCheckingManagedCopy { return "Checking the private game copy" }
        if managedHealth == .invalidReference { return "Re-add this game" }
        if needsRepair { return "Repair this game’s private copy" }
        if let requiredFirmware { return "Set up \(requiredFirmware.title) and play" }
        return "Play \(game.title)"
    }

    private var readinessStatus: (title: String, symbol: String, color: Color)? {
        if isRepairingManagedCopy {
            return ("Repairing copy…", "wrench.and.screwdriver.fill", SwanTheme.cyan)
        }
        if isCheckingManagedCopy {
            return ("Checking copy…", "checkmark.shield", Color.secondary)
        }
        if managedHealth == .missing {
            return ("Game copy missing", "externaldrive.badge.exclamationmark", Color.red)
        }
        if managedHealth == .changed {
            return ("Repair needed", "exclamationmark.shield.fill", Color.orange)
        }
        if managedHealth == .invalidReference {
            return ("Re-add needed", "exclamationmark.octagon.fill", Color.red)
        }
        if let requiredFirmware {
            return ("\(requiredFirmware.title) file required", "exclamationmark.circle.fill", Color.orange)
        }
        if !canPlay {
            return ("Playback unavailable", "exclamationmark.triangle.fill", Color.secondary)
        }
        return nil
    }
}

private struct GameArtworkTile: View {
    let game: GameRecord
    let artwork: GameArtworkRecord?

    var body: some View {
        ZStack {
            if let image = artwork.flatMap({ NSImage(data: $0.pngData) }) {
                Color.black.opacity(0.94)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .blur(radius: 14)
                    .scaleEffect(1.14)
                    .opacity(0.52)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                LinearGradient(
                    colors: [.black.opacity(0.18), .black.opacity(0.48)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(12)
                    .shadow(color: .black.opacity(0.46), radius: 10, y: 5)
            } else {
                proceduralArtwork
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.38), location: 0),
                    .init(color: .clear, location: 0.34),
                    .init(color: .clear, location: 0.68),
                    .init(color: .black.opacity(0.38), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack {
                    artworkPill(systemBadge)
                    Spacer()
                }
                Spacer()
                HStack {
                    artworkPill(systemDescriptor)
                    Spacer()
                    if game.metadata.hasRTC {
                        artworkPill("RTC", symbol: "clock")
                    }
                }
            }
            .padding(11)
        }
        .background(.black)
        .accessibilityHidden(true)
    }

    private var proceduralArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardGradient)
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: 18)
                .frame(width: 145, height: 145)
                .offset(x: 76, y: -53)
            Capsule()
                .fill(.white.opacity(0.07))
                .frame(width: 170, height: 38)
                .rotationEffect(.degrees(-28))
                .offset(x: -72, y: 63)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(0.24))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
                Image(systemName: game.resolvedHardwareModel == .pocketChallengeV2
                    ? "rectangle.stack.fill"
                    : game.metadata.isColor
                        ? "sparkles.rectangle.stack"
                        : "rectangle.stack")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: 92, height: 70)
            .rotationEffect(.degrees(-3))
            .shadow(color: .black.opacity(0.22), radius: 9, y: 6)
        }
    }

    private func artworkPill(_ title: String, symbol: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(title)
        }
        .font(.caption2.monospaced().weight(.black))
        .tracking(0.9)
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.52), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
    }

    private var systemBadge: String {
        switch game.resolvedHardwareModel {
        case .pocketChallengeV2: "PCV2"
        case .wonderSwanColor, .swanCrystal: "WSC"
        case .automatic, .wonderSwan: "WS"
        }
    }

    private var systemDescriptor: String {
        switch game.resolvedHardwareModel {
        case .pocketChallengeV2: "POCKET CHALLENGE V2"
        case .wonderSwanColor, .swanCrystal: "COLOR"
        case .automatic, .wonderSwan: "MONOCHROME"
        }
    }

    private var cardGradient: LinearGradient {
        let hue = Double(game.metadata.computedChecksum % 360) / 360.0
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.68, brightness: 0.72),
                Color(
                    hue: (hue + 0.12).truncatingRemainder(dividingBy: 1),
                    saturation: 0.82,
                    brightness: 0.36
                ),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension GameLaunchReadiness {
    var confidenceTitle: String {
        switch self {
        case .ready: "Ready to launch"
        case .checkingGame: "Checking game copy"
        case .gameUnavailable: "Game copy unavailable"
        case .startupFileRequired: "Startup file required"
        case .engineUnavailable: "Playback engine unavailable"
        }
    }

    var confidenceDetail: String {
        switch self {
        case .ready:
            "The native engine, matching startup file, and local game bytes are available."
        case .checkingGame:
            "SwanSong is checking the private game copy before allowing play."
        case .gameUnavailable:
            "Repair or re-add the exact game before trying to play."
        case .startupFileRequired:
            "Add the matching system startup file once, then this game can launch."
        case .engineUnavailable:
            "The native SwanSong playback engine is not currently available."
        }
    }

    var confidenceSymbol: String {
        switch self {
        case .ready: "play.circle.fill"
        case .checkingGame: "checkmark.shield"
        case .gameUnavailable: "externaldrive.badge.exclamationmark"
        case .startupFileRequired: "cpu"
        case .engineUnavailable: "exclamationmark.triangle.fill"
        }
    }

    var confidenceColor: Color {
        switch self {
        case .ready: .green
        case .checkingGame: SwanTheme.cyan
        case .gameUnavailable: .red
        case .startupFileRequired: .orange
        case .engineUnavailable: .secondary
        }
    }
}

private extension GameCompatibilityStatus {
    var confidenceDetail: String {
        switch self {
        case .untested:
            "No local play evidence or personal verdict has been recorded for this exact game."
        case .reachedVideo:
            "SwanSong observed a non-uniform native game picture. This is not confirmation of gameplay or hardware accuracy."
        case .confirmedWorks:
            "You marked this exact game as working. This personal verdict is independent from launch setup and ROM integrity."
        case .reportedIssues:
            "You reported compatibility issues for this exact game. Add a note below to preserve what needs attention."
        }
    }
}

private extension GameROMIntegrity {
    var confidenceTitle: String {
        switch self {
        case .verified: "Verified managed copy"
        case .checksumMismatch: "Footer checksum mismatch"
        case .checking: "Checking exact bytes"
        case .missing: "Private copy missing"
        case .changed: "Private copy changed"
        case .invalidReference: "Library identity invalid"
        case .unmanaged: "Original-location game"
        }
    }

    var confidenceDetail: String {
        switch self {
        case .verified:
            "The managed bytes and WonderSwan footer checksum match the identity saved at import."
        case .checksumMismatch:
            "The WonderSwan footer checksum does not match. This is an integrity warning, not a compatibility verdict."
        case .checking:
            "SwanSong is validating the local game bytes and saved library identity."
        case .missing:
            "The private managed copy is missing and must be repaired from the exact original."
        case .changed:
            "The managed bytes changed after import and must be repaired before play."
        case .invalidReference:
            "This library entry cannot prove which managed copy belongs to it; re-add the original as a new entry."
        case .unmanaged:
            "This legacy entry runs from its original location instead of a SwanSong managed copy."
        }
    }

    var confidenceSymbol: String {
        switch self {
        case .verified: "checkmark.shield.fill"
        case .checksumMismatch: "exclamationmark.triangle.fill"
        case .checking: "checkmark.shield"
        case .missing: "externaldrive.badge.xmark"
        case .changed: "exclamationmark.shield.fill"
        case .invalidReference: "exclamationmark.octagon.fill"
        case .unmanaged: "folder"
        }
    }

    var confidenceColor: Color {
        switch self {
        case .verified: .green
        case .checksumMismatch: .orange
        case .checking: SwanTheme.cyan
        case .missing, .invalidReference: .red
        case .changed: .orange
        case .unmanaged: .secondary
        }
    }
}

private struct GameConfidenceRow: View {
    let lane: String
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let accessibilityIdentifier: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(lane.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.75)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.16), lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lane): \(title). \(detail)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct GameConfidencePanel: View {
    let confidence: GameConfidence
    let evidence: GameCompatibilityEvidence?
    @Binding var noteDraft: String
    let onSetVerdict: (GameCompatibilityVerdict?) -> Void
    let onSaveNote: (String) -> Void
    let geometryProbe: GameConfidenceGeometryProbe?
    @State private var showsCheckExplanations = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [SwanTheme.violet, SwanTheme.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "checkmark.seal.text.page.fill")
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Game Confidence")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("Three independent signals for this exact game.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GameConfidenceRow(
                lane: "Launch readiness",
                title: confidence.launchReadiness.confidenceTitle,
                detail: confidence.launchReadiness.confidenceDetail,
                symbol: confidence.launchReadiness.confidenceSymbol,
                color: confidence.launchReadiness.confidenceColor,
                accessibilityIdentifier: GameConfidenceAccessibility.launchReadiness
            )

            GameConfidenceRow(
                lane: "Compatibility evidence",
                title: confidence.compatibility.confidenceTitle,
                detail: confidence.compatibility.confidenceDetail,
                symbol: confidence.compatibility.confidenceSymbol,
                color: confidence.compatibility.confidenceColor,
                accessibilityIdentifier: GameConfidenceAccessibility.compatibilityEvidence
            )

            GameConfidenceRow(
                lane: "ROM integrity",
                title: confidence.romIntegrity.confidenceTitle,
                detail: confidence.romIntegrity.confidenceDetail,
                symbol: confidence.romIntegrity.confidenceSymbol,
                color: confidence.romIntegrity.confidenceColor,
                accessibilityIdentifier: GameConfidenceAccessibility.romIntegrity
            )

            DisclosureGroup(
                "What these checks mean",
                isExpanded: $showsCheckExplanations
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    confidenceExplanation(
                        "Launch readiness",
                        detail: confidence.launchReadiness.confidenceDetail
                    )
                    confidenceExplanation(
                        "Compatibility evidence",
                        detail: confidence.compatibility.confidenceDetail
                    )
                    confidenceExplanation(
                        "ROM integrity",
                        detail: confidence.romIntegrity.confidenceDetail
                    )

                    if confidence.compatibility == .reachedVideo {
                        Label(
                            "Reached video confirms only a non-uniform native game raster—not gameplay, controls, audio, timing, saves, or hardware accuracy.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption.weight(.semibold))
            .accessibilityIdentifier(GameInspectorAccessibility.confidenceExplanations)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Your compatibility verdict")
                    .font(.subheadline.weight(.semibold))
                Text("Record your experience without changing the checks above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                verdictControls
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Compatibility note")
                        .font(.subheadline.weight(.semibold))
                    Text("Optional")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                TextEditor(text: $noteDraft)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 64, maxHeight: 96)
                    .background(.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(.separator.opacity(0.55))
                    }
                    .accessibilityLabel("Optional compatibility note")
                    .accessibilityIdentifier(GameConfidenceAccessibility.note)

                HStack {
                    Text("Stored only in this Mac’s private SwanSong library.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 8)
                    Button("Save Note", systemImage: "checkmark") {
                        onSaveNote(noteDraft)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!noteHasChanges)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier(GameConfidenceAccessibility.saveNote)
                    .background(
                        GameConfidenceActionGeometryReader(
                            identifier: GameConfidenceAccessibility.saveNote,
                            probe: geometryProbe
                        )
                    )
                }
            }

        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [SwanTheme.violet.opacity(0.08), SwanTheme.cyan.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(SwanTheme.accent.opacity(0.18), lineWidth: 0.75)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(GameConfidenceAccessibility.panel)
    }

    private func confidenceExplanation(
        _ title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var noteHasChanges: Bool {
        normalizedNote(noteDraft) != normalizedNote(evidence?.note ?? "")
    }

    private func normalizedNote(_ note: String) -> String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var verdictControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                worksButton
                issuesButton
                clearVerdictButton
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 7) {
                worksButton
                issuesButton
                clearVerdictButton
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(GameConfidenceAccessibility.verdictControls)
    }

    private var worksButton: some View {
        verdictButton(
            "Works",
            symbol: "checkmark.circle.fill",
            verdict: .works,
            tint: .green,
            accessibilityIdentifier: GameConfidenceAccessibility.verdictWorks
        )
        .background(
            GameConfidenceActionGeometryReader(
                identifier: GameConfidenceAccessibility.verdictWorks,
                probe: geometryProbe
            )
        )
    }

    private var issuesButton: some View {
        verdictButton(
            "Issues",
            symbol: "exclamationmark.bubble.fill",
            verdict: .issues,
            tint: .orange,
            accessibilityIdentifier: GameConfidenceAccessibility.verdictIssues
        )
        .background(
            GameConfidenceActionGeometryReader(
                identifier: GameConfidenceAccessibility.verdictIssues,
                probe: geometryProbe
            )
        )
    }

    @ViewBuilder
    private func verdictButton(
        _ title: String,
        symbol: String,
        verdict: GameCompatibilityVerdict,
        tint: Color,
        accessibilityIdentifier: String
    ) -> some View {
        let isSelected = evidence?.verdict == verdict
        if isSelected {
            Button(title, systemImage: symbol) {
                onSetVerdict(verdict)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
            .accessibilityValue("Selected")
            .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            Button(title, systemImage: symbol) {
                onSetVerdict(verdict)
            }
            .buttonStyle(.bordered)
            .tint(tint)
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
            .accessibilityValue("Not selected")
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    private var clearVerdictButton: some View {
        Button("Clear verdict", systemImage: "xmark.circle") {
            onSetVerdict(nil)
        }
        .buttonStyle(.borderless)
        .disabled(evidence?.verdict == nil)
        .frame(minWidth: 28, minHeight: 28)
        .contentShape(Rectangle())
        .accessibilityHint("Keeps automatic reached-video evidence and the optional note")
        .accessibilityIdentifier(GameConfidenceAccessibility.verdictClear)
        .background(
            GameConfidenceActionGeometryReader(
                identifier: GameConfidenceAccessibility.verdictClear,
                probe: geometryProbe
            )
        )
    }
}

struct GameInspector: View {
    let game: GameRecord
    let artwork: GameArtworkRecord?
    let confidence: GameConfidence
    let canPlay: Bool
    let managedHealth: ManagedGameHealth?
    let isCheckingManagedCopy: Bool
    let isRepairingManagedCopy: Bool
    let requiredFirmware: WonderSwanFirmwareKind?
    let canImportSave: Bool
    let canExportSave: Bool
    let onPlay: () -> Void
    let onRepair: () -> Void
    let onReAdd: () -> Void
    let onInstallFirmware: () -> Void
    let onImportSave: () -> Void
    let onExportSave: () -> Void
    let onSetCompatibilityVerdict: (GameCompatibilityVerdict?) -> Void
    let onSaveCompatibilityNote: (String) -> Void
    let geometryProbe: GameConfidenceGeometryProbe?
    @State private var compatibilityNoteDraft = ""
    @State private var showsGameDetails = false
    @State private var showsSaveTools = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    GameArtworkTile(game: game, artwork: artwork)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(.separator.opacity(0.55), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(game.title)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                            .accessibilityAddTraits(.isHeader)
                        Text(game.systemTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier(GameInspectorAccessibility.systemIdentity)
                    }

                    Label(runtimeDetail, systemImage: runtimeDetailSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(runtimeDetailColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(runtimeDetailColor.opacity(0.10), in: Capsule())
                        .accessibilityIdentifier(GameInspectorAccessibility.runtimeStatus)

                    primaryAction
                        .controlSize(.large)
                }

                GameConfidencePanel(
                    confidence: confidence,
                    evidence: game.compatibilityEvidence,
                    noteDraft: $compatibilityNoteDraft,
                    onSetVerdict: onSetCompatibilityVerdict,
                    onSaveNote: onSaveCompatibilityNote,
                    geometryProbe: geometryProbe
                )

                DisclosureGroup("Game Details", isExpanded: $showsGameDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("System", value: game.systemTitle)
                        LabeledContent(
                            "Size",
                            value: ByteCountFormatter.string(
                                fromByteCount: Int64(game.metadata.fileSize),
                                countStyle: .file
                            )
                        )
                        if let artwork {
                            LabeledContent(
                                "Last capture",
                                value: artwork.manifest.isVertical ? "Vertical" : "Horizontal"
                            )
                        }
                        if game.metadata.hasRTC {
                            LabeledContent("Real-time clock", value: "Supported")
                        }
                    }
                    .font(.callout)
                    .padding(.top, 8)
                }
                .font(.headline)
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityIdentifier(GameInspectorAccessibility.gameDetails)

                if game.resolvedHardwareModel == .pocketChallengeV2 {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Program Flash", systemImage: "memorychip.fill")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text("Progress is saved automatically as a private, identity-bound cartridge-flash image.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(
                        GameInspectorAccessibility.pocketChallengeProgramFlash
                    )
                } else {
                    DisclosureGroup("Pocket Save", isExpanded: $showsSaveTools) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Move compatible cartridge-save data between SwanSong and Analogue Pocket.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(action: onImportSave) {
                                Label("Import Save…", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 28)
                            .disabled(!canImportSave)
                            Button(action: onExportSave) {
                                Label("Export Save…", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 28)
                            .disabled(!canExportSave)
                        }
                        .padding(.top, 8)
                    }
                    .font(.headline)
                    .padding(12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityIdentifier(GameInspectorAccessibility.pocketSave)
                }
            }
        }
        .coordinateSpace(name: GameConfidenceGeometryProbe.coordinateSpace)
        .background(
            GameConfidenceViewportGeometryReader(probe: geometryProbe)
        )
        .padding(16)
        .accessibilityElement(children: .contain)
        .onAppear {
            compatibilityNoteDraft = game.compatibilityEvidence?.note ?? ""
        }
        .onChange(of: game.compatibilityEvidence?.note) { _, note in
            compatibilityNoteDraft = note ?? ""
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if isRepairingManagedCopy {
            Button {} label: {
                Label("Repairing…", systemImage: "wrench.and.screwdriver.fill")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.borderedProminent)
                .disabled(true)
                .help("Verifying and restoring the private game copy")
        } else if isCheckingManagedCopy {
            Button {} label: {
                Label("Checking…", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.bordered)
                .disabled(true)
                .help("Verifying the private game copy")
        } else if managedHealth == .invalidReference {
            Button(action: onReAdd) {
                Label("Re-add Game…", systemImage: "plus.rectangle.on.folder")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.borderedProminent)
                .help("Add the original game again as a new, verified library entry")
        } else if needsRepair {
            Button(action: onRepair) {
                Label("Repair…", systemImage: "wrench.and.screwdriver.fill")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.borderedProminent)
                .help("Choose the exact original game file to repair this private copy")
                .accessibilityLabel("Repair \(game.title)’s private copy")
        } else if let requiredFirmware {
            Button(action: onInstallFirmware) {
                Label("Set Up \(requiredFirmware.title) & Play…", systemImage: "cpu")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.borderedProminent)
                .help("Set up the required \(requiredFirmware.title) startup file, then play")
                .accessibilityLabel("Set up \(requiredFirmware.title) startup file and play")
        } else {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.borderedProminent)
                .disabled(!canPlay)
                .help("Play")
        }
    }

    private var runtimeDetail: String {
        if isRepairingManagedCopy {
            return "Repairing private copy…"
        }
        if isCheckingManagedCopy {
            return "Checking private copy…"
        }
        if managedHealth == .missing {
            return "Private copy missing · choose the exact original file"
        }
        if managedHealth == .changed {
            return "Private copy changed · verification repair needed"
        }
        if managedHealth == .invalidReference {
            return "Library identity invalid · re-add as a new entry"
        }
        if let requiredFirmware {
            return "\(requiredFirmware.title) startup file setup needed"
        }
        return canPlay ? "Ready to play" : "Playback engine unavailable"
    }

    private var runtimeDetailColor: Color {
        if isRepairingManagedCopy { return SwanTheme.cyan }
        if isCheckingManagedCopy { return .secondary }
        if managedHealth == .missing { return .red }
        if managedHealth == .invalidReference { return .red }
        if managedHealth == .changed || requiredFirmware != nil { return .orange }
        return canPlay ? .green : .secondary
    }

    private var runtimeDetailSymbol: String {
        if isRepairingManagedCopy { return "wrench.and.screwdriver.fill" }
        if isCheckingManagedCopy { return "checkmark.shield" }
        if managedHealth == .missing { return "externaldrive.badge.xmark" }
        if managedHealth == .invalidReference { return "exclamationmark.octagon.fill" }
        if managedHealth == .changed { return "exclamationmark.triangle.fill" }
        if requiredFirmware != nil { return "cpu" }
        return canPlay ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var needsRepair: Bool {
        managedHealth == .missing || managedHealth == .changed
    }
}

struct PlayerCanvasFrame<Content: View>: View {
    let chromeColor: Color
    let chromeLineWidth: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(4)
            .background(
                Color.black.opacity(0.82),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(chromeColor, lineWidth: chromeLineWidth)
                    .accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(0.40), radius: 24, y: 12)
    }
}

private struct PlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @Bindable var model: AppModel
    @AppStorage("automaticallyFitGameOrientation") private var automaticallyFitGameOrientation = true
    @AppStorage("displayProfile") private var displayProfileRaw = DisplayProfile.purePixels.rawValue
    @AppStorage("didDismissPlayerInputHint") private var didDismissPlayerInputHint = false
    @AppStorage("didDismissPocketChallengeV2InputHint") private var didDismissPocketChallengeV2InputHint = false
    @AppStorage("lcdResponseScale") private var lcdResponseScale = 1.0
    @AppStorage("showPlayerDiagnostics") private var showPlayerDiagnostics = false
    @State private var isInputGuidePresented = false
    @State private var isTranslationTestCaseNamingPresented = false
    @State private var showsFailureDetails = false
    @State private var awaitsRecoveryFrame = false
    @FocusState private var gameplayHasFocus: Bool
    @FocusState private var launchRecoveryActionHasFocus: Bool
    @AccessibilityFocusState private var failureHeadingHasFocus: Bool

    var body: some View {
        ZStack {
            SwanTheme.playerBackground
                .ignoresSafeArea()

            RadialGradient(
                colors: [SwanTheme.cyan.opacity(0.055), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 720
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [SwanTheme.violet.opacity(0.050), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 680
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                if model.playerIsInteractive,
                   let phase = model.translationComparisonPhase,
                   phase.role != nil {
                    translationComparisonBanner(phase)
                } else if model.playerIsInteractive,
                          model.translationRouteRecordingIsPreparing
                            || model.translationRouteIsRecording {
                    translationRecordingBanner
                }

                Spacer(minLength: 0)
                playerStage
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .accessibilityIdentifier("player-root")
        .navigationTitle(model.playingGame?.title ?? "Player")
        .tint(SwanTheme.accent)
        .toolbar {
            playerToolbar
        }
        .onAppear(perform: requestGameplayFocus)
        .onChange(of: model.playingGameID) { _, _ in requestGameplayFocus() }
        .onChange(of: model.playerIsInteractive, initial: true) { _, isInteractive in
            guard isInteractive else { return }
            requestGameplayFocus()
        }
        .onChange(of: model.playerFailure?.id) { _, failureID in
            guard failureID != nil, let failure = model.playerFailure else {
                failureHeadingHasFocus = false
                return
            }
            awaitsRecoveryFrame = false
            showsFailureDetails = false
            gameplayHasFocus = false
            model.clearKeyboardInput()
            Task { @MainActor in
                await Task.yield()
                failureHeadingHasFocus = true
            }
            let recovery = model.playerFailureCanRetry
                ? "\(model.playerFailureRetryTitle) is available."
                : "\(model.playerFailureReturnTitle) is available."
            postAccessibilityAnnouncement(
                "\(failure.headline). \(recovery)",
                priority: .high
            )
        }
        .onChange(of: model.currentFrame?.number) { _, frameNumber in
            guard awaitsRecoveryFrame,
                  frameNumber != nil,
                  model.playerIsInteractive,
                  !model.isLaunchingGame else { return }
            awaitsRecoveryFrame = false
            requestGameplayFocus()
        }
        .onChange(of: gameplayHasFocus) { _, focused in
            if !focused { model.clearKeyboardInput() }
        }
        .onChange(of: isInputGuidePresented) { _, presented in
            if !presented { requestGameplayFocus() }
        }
        .onChange(of: displayProfileRaw) { _, _ in requestGameplayFocus() }
        .onChange(of: lcdResponseScale) { _, _ in requestGameplayFocus() }
        .onChange(of: model.activePlayerInput) { _, input in
            if !input.isEmpty { dismissCurrentPlayerInputHint() }
        }
        .onChange(of: model.translationTestCaseNamingRequestID) { _, _ in
            isTranslationTestCaseNamingPresented = true
        }
        .onChange(of: model.playerLaunchNeedsAttention) { _, needsAttention in
            guard needsAttention else {
                launchRecoveryActionHasFocus = false
                if model.playerIsInteractive, model.currentFrame != nil {
                    requestGameplayFocus()
                }
                return
            }
            gameplayHasFocus = false
            model.clearKeyboardInput()
            Task { @MainActor in
                await Task.yield()
                launchRecoveryActionHasFocus = true
            }
            postAccessibilityAnnouncement(
                launchAttentionAnnouncement,
                priority: .high
            )
        }
        .onChange(of: model.playerVideoActivityNeedsAttention) { _, needsAttention in
            guard needsAttention else { return }
            postAccessibilityAnnouncement(
                playerVideoActivityAnnouncement,
                priority: .high
            )
        }
        .sheet(
            isPresented: $model.isRewindPresented,
            onDismiss: {
                model.dismissRewind()
                requestGameplayFocus()
            }
        ) {
            RewindTimeRibbonView(model: model)
                .interactiveDismissDisabled(model.playerStateOperationIsBusy)
        }
        .sheet(
            isPresented: $model.isStateTimelinePresented,
            onDismiss: {
                model.dismissStateTimeline()
                requestGameplayFocus()
            }
        ) {
            StateTimelineView(model: model)
                .frame(minWidth: 760, minHeight: 430)
                .interactiveDismissDisabled(model.playerStateOperationIsBusy)
        }
        .sheet(isPresented: $isTranslationTestCaseNamingPresented) {
            TranslationTestCaseNamingView(
                model: model,
                onCancel: {
                    isTranslationTestCaseNamingPresented = false
                    requestGameplayFocus()
                },
                onSave: {
                    guard model.saveSelectedTranslationTestCase() else { return }
                    isTranslationTestCaseNamingPresented = false
                    requestGameplayFocus()
                },
                onSaveAndVerify: {
                    guard model.saveSelectedTranslationTestCase() else { return }
                    isTranslationTestCaseNamingPresented = false
                    model.stopPlaying()
                    model.verifyLatestTranslationRoute()
                }
            )
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: currentPlayerInputHintIsDismissed
        )
    }

    private var gameSurface: some View {
        ZStack {
            Color.black

            if let frame = model.currentFrame {
                MetalScreenView(
                    frame: frame,
                    profile: displayProfile,
                    responseScale: Float(lcdMotionLevel.responseScale)
                )
                .aspectRatio(
                    CGFloat(frame.width) / CGFloat(frame.height),
                    contentMode: .fit
                )
                .accessibilityHidden(true)
            } else if model.playerFailure == nil {
                playerLaunchView
            }
        }
        .aspectRatio(playerAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.playerIsInteractive { requestGameplayFocus() }
        }
        .focusable()
        .focused($gameplayHasFocus)
        .focusEffectDisabled()
        .onKeyPress(phases: .all, action: handleKeyPress)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: gameplayHasFocus)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.isPaused)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.playerFailure?.id)
        .accessibilityIdentifier("player-game-surface")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            model.playingGame?.resolvedHardwareModel == .pocketChallengeV2
                ? "Pocket Challenge V2 display"
                : "WonderSwan game display"
        )
        .accessibilityValue(playerSurfaceAccessibilityValue)
        .accessibilityHint(playerSurfaceAccessibilityHint)
        .accessibilityAction(
            named: playerSurfaceAccessibilityActionTitle
        ) {
            if model.playerIsInteractive {
                requestGameplayFocus()
            } else if model.playerFailureCanRetry {
                retryPlayerFailure()
            } else if model.playerFailure != nil {
                model.stopPlaying()
            }
        }
    }

    private var playerCanvas: some View {
        PlayerCanvasFrame(
            chromeColor: playerCanvasChromeColor,
            chromeLineWidth: playerCanvasChromeLineWidth
        ) {
            gameSurface
        }
    }

    private var playerStage: some View {
        VStack(spacing: 12) {
            if model.currentFrame != nil || model.playerFailure == nil {
                playerCanvas
            }

            if let failure = model.playerFailure {
                playerFailureCard(
                    failure,
                    overLastFrame: model.currentFrame != nil
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .scale(scale: 0.97).combined(with: .opacity)
                )
            }

            if model.playerIsInteractive,
               model.playerVideoActivityNeedsAttention {
                playerVideoActivityCard
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
            }

            if shouldShowPlayerStatus,
               !model.playerVideoActivityNeedsAttention,
               model.playerFailure == nil {
                playerStatus
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
            }

            if model.playerIsInteractive,
               model.currentFrame != nil,
               !currentPlayerInputHintIsDismissed,
               model.playerFailure == nil {
                playerInputHint
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
            }
        }
        .frame(maxWidth: 1180, maxHeight: .infinity)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: model.playerVideoActivityNeedsAttention
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: shouldShowPlayerStatus
        )
    }

    private var playerLaunchView: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SwanTheme.violet.opacity(0.34), SwanTheme.cyan.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if model.playerLaunchNeedsAttention {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: launchStageSymbol)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(SwanTheme.cyan)
                        .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                }
            }
            .frame(width: 66, height: 66)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(launchHeadline)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(launchDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 7) {
                ProgressView(value: model.playerLaunchStage?.progress ?? 0.06)
                    .progressViewStyle(.linear)
                    .tint(model.playerLaunchNeedsAttention ? .orange : SwanTheme.cyan)
                    .frame(maxWidth: 330)
                    .accessibilityLabel("Game launch progress")
                    .accessibilityValue(launchStageTitle)
                    .accessibilityIdentifier("player-launch-progress")
                Text(launchStageTitle)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if model.playerLaunchNeedsAttention {
                playerLaunchRecoveryActions
            }
        }
        .padding(30)
        .frame(maxWidth: 520)
        .accessibilityIdentifier("player-launch")
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var playerLaunchRecoveryActions: some View {
        if model.playerLaunchStage == .closingPreviousSession {
            Button("Back to Library", systemImage: "chevron.backward") {
                model.stopPlaying()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .focused($launchRecoveryActionHasFocus)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) {
                    launchTryAgainButton
                    if launchShowsStartupFileRecovery {
                        launchStartupFileButton
                    }
                    launchBackToLibraryButton
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(spacing: 8) {
                    launchTryAgainButton
                    if launchShowsStartupFileRecovery {
                        launchStartupFileButton
                    }
                    launchBackToLibraryButton
                }
                .frame(maxWidth: 300)
            }
        }
    }

    private var launchTryAgainButton: some View {
        Button("Try Again", systemImage: "arrow.clockwise") {
            model.restartCurrentSession()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .focused($launchRecoveryActionHasFocus)
    }

    private var launchStartupFileButton: some View {
        Button(startupFileReplacementTitle, systemImage: "cpu") {
            model.replaceStartupFileAndRetryCurrentSession()
        }
        .buttonStyle(.bordered)
        .disabled(model.playerStateOperationIsBusy || model.firmwareImportIsBusy)
    }

    private var launchBackToLibraryButton: some View {
        Button("Back to Library", systemImage: "chevron.backward") {
            model.stopPlaying()
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(.cancelAction)
    }

    private func playerFailureCard(
        _ failure: PlayerFailureState,
        overLastFrame: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: overLastFrame ? 14 : 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.red.opacity(0.34), .orange.opacity(0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: overLastFrame ? 20 : 24, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .frame(
                    width: overLastFrame ? 46 : 54,
                    height: overLastFrame ? 46 : 54
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(failure.headline)
                        .font(overLastFrame ? .title3.weight(.semibold) : .title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($failureHeadingHasFocus)
                    Text(failure.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("What happened", systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if failure.detail.count > 180 {
                        Button(showsFailureDetails ? "Show Less" : "Show All") {
                            showsFailureDetails.toggle()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                    }
                }
                Text(failure.detail)
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.86))
                    .textSelection(.enabled)
                    .lineLimit(showsFailureDetails ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    failureSafetyText(overLastFrame: overLastFrame)
                    Spacer(minLength: 12)
                    playerFailureActions
                }
                VStack(alignment: .leading, spacing: 10) {
                    failureSafetyText(overLastFrame: overLastFrame)
                    playerFailureActions
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(overLastFrame ? 18 : 24)
        .frame(maxWidth: overLastFrame ? 470 : 530)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 24, y: 12)
        .accessibilityIdentifier("player-failure")
        .accessibilityElement(children: .contain)
    }

    private func failureSafetyText(overLastFrame: Bool) -> some View {
        Text(
            overLastFrame
                ? "The emulator was unloaded; the last frame is preserved for reference."
                : "The emulator was safely unloaded."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var playerFailureActions: some View {
        HStack(spacing: 10) {
            Button(model.playerFailureReturnTitle) {
                model.stopPlaying()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("player-failure-return")

            if model.playerFailureCanRetry {
                Button(model.playerFailureRetryTitle) {
                    retryPlayerFailure()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("player-failure-retry")
            }
        }
    }

    private var playerVideoActivityCard: some View {
        PlayerVideoActivityRecoveryCard(
            headline: playerVideoActivityHeadline,
            detail: playerVideoActivityDetail,
            startupFileAccessibilityTitle: startupFileReplacementTitle,
            restartIsDisabled: model.playerStateOperationIsBusy,
            startupFileActionIsDisabled: model.playerStateOperationIsBusy
                || model.firmwareImportIsBusy,
            onTryControls: {
                model.dismissPlayerVideoActivityDiagnostic()
                requestGameplayFocus()
            },
            onRestart: model.restartCurrentSession,
            onReplaceStartupFile: model.replaceStartupFileAndRetryCurrentSession,
            onDismiss: model.dismissPlayerVideoActivityDiagnostic
        )
    }

    @ToolbarContentBuilder
    private var playerToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: model.stopPlaying) {
                Label(
                    model.activeTranslationRole == nil ? "Library" : "Translation Lab",
                    systemImage: "chevron.backward"
                )
            }
            .help(model.activeTranslationRole == nil ? "Back to Library" : "Back to Translation Lab")
            .accessibilityLabel(
                model.activeTranslationRole == nil ? "Back to Library" : "Back to Translation Lab"
            )
            .accessibilityIdentifier("player-back")
            .disabled(
                model.translationRouteIsRecording
                    || model.translationRouteRecordingIsPreparing
            )
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if model.playerIsInteractive,
               let role = model.activeTranslationRole {
                translationRuntimeMenu(role)
            }
            displayMenu

            ControlGroup {
                Button(action: model.showRewind) {
                    Image(systemName: "gobackward")
                }
                .help(
                    model.canShowRewind
                        ? "Open Time Ribbon (\(model.rewindRetainedSeconds.formatted(.number.precision(.fractionLength(1)))) seconds available)"
                        : "Keep playing briefly to build rewind history"
                )
                .accessibilityLabel("Open Time Ribbon")
                .accessibilityValue(
                    model.canShowRewind
                        ? "\(model.rewindCheckpoints.count) recent moments"
                        : "Rewind history not ready"
                )
                .accessibilityIdentifier("player-rewind")
                .disabled(!model.canShowRewind)
                Button(action: model.togglePause) {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .help(model.isPaused ? "Resume" : "Pause")
                .accessibilityLabel(model.isPaused ? "Resume emulation" : "Pause emulation")
                .accessibilityValue(model.isPaused ? "Paused" : "Playing")
                .accessibilityIdentifier("player-pause")
                .disabled(!model.canTogglePause)
                Button(action: model.advanceOneFrame) {
                    Image(systemName: "forward.frame.fill")
                }
                .help("Advance One Frame")
                .accessibilityLabel("Advance one frame")
                .accessibilityHint("Runs exactly one emulated frame and remains paused")
                .accessibilityIdentifier("player-step")
                .disabled(!model.canAdvanceFrame)
                Button(action: model.toggleFastForward) {
                    Image(systemName: "forward.fill")
                }
                .help(model.isFastForwarding ? "Return to Normal Speed" : "Fast Forward")
                .accessibilityLabel(
                    model.isFastForwarding ? "Disable Fast Forward" : "Enable Fast Forward"
                )
                .accessibilityValue(model.isFastForwarding ? "On" : "Off")
                .accessibilityIdentifier("player-fast-forward")
                .tint(model.isFastForwarding ? .orange : nil)
                .disabled(!model.canToggleFastForward)
            }

            Button {
                isInputGuidePresented.toggle()
            } label: {
                Image(systemName: model.connectedControllerName == nil ? "gamecontroller" : "gamecontroller.fill")
            }
            .help(
                model.playingGame?.resolvedHardwareModel == .pocketChallengeV2
                    ? "Pocket Challenge V2 Controls"
                    : "WonderSwan Controls"
            )
            .accessibilityLabel(
                model.playingGame?.resolvedHardwareModel == .pocketChallengeV2
                    ? "Pocket Challenge V2 controls"
                    : "WonderSwan controls"
            )
            .accessibilityValue(model.connectedControllerName ?? "Keyboard")
            .popover(isPresented: $isInputGuidePresented, arrowEdge: .bottom) {
                InputGuideView(
                    controllerName: model.connectedControllerName,
                    activeInput: model.activePlayerInput,
                    controllerProfile: model.controllerProfile,
                    hardwareModel: model.playingGame?.resolvedHardwareModel ?? .automatic
                )
            }

            Menu {
                Button(action: model.resetGame) {
                    Label("Reset Game", systemImage: "arrow.counterclockwise")
                }
                .disabled(!model.canResetGame)
                .accessibilityIdentifier("player-reset")

                Divider()

                Button(action: model.captureScreenshot) {
                    Label("Save Screenshot…", systemImage: "camera")
                }
                .disabled(model.currentFrame == nil)

                Button(action: model.useCurrentFrameAsLibraryArtwork) {
                    Label("Use Current Frame as Library Artwork", systemImage: "photo.badge.checkmark")
                }
                .disabled(model.currentFrame == nil || model.activeTranslationRole != nil)
                .help("Stores the current gameplay image only on this Mac")
                .accessibilityHint("Replaces this game’s library image with the current gameplay screen and stores it only on this Mac")

                Button(action: model.exportPocketSave) {
                    Label("Export Pocket Save…", systemImage: "externaldrive.badge.checkmark")
                }
                .disabled(!model.canExportPocketSave)

                Divider()

                Button(action: model.saveQuickState) {
                    Label("Save Quick State", systemImage: "square.and.arrow.down")
                }
                .disabled(
                    !model.playerIsInteractive
                        || model.currentFrame == nil
                        || model.activeTranslationRole != nil
                        || model.playerStateOperationIsBusy
                )
                Button(action: model.loadQuickState) {
                    Label("Load Quick State", systemImage: "clock.arrow.circlepath")
                }
                .disabled(
                    !model.playerIsInteractive
                        || model.quickStateSavedAt == nil
                        || model.activeTranslationRole != nil
                        || model.playerStateOperationIsBusy
                )
                Button(action: model.showStateTimeline) {
                    Label("Save-State Timeline…", systemImage: "rectangle.stack")
                }
                .disabled(
                    !model.playerIsInteractive
                        || model.activeTranslationRole != nil
                        || model.playerStateOperationIsBusy
                )

                Button(action: model.rewindFiveSeconds) {
                    Label("Rewind 5 Seconds", systemImage: "gobackward.5")
                }
                .disabled(!model.canShowRewind)

                Divider()

                Button(action: model.toggleFullScreen) {
                    Label("Toggle Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityIdentifier("player-fullscreen")
            } label: {
                Label("More Player Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .help("More Player Actions")
            .accessibilityLabel("More Player Actions")
            .accessibilityIdentifier("player-more-actions")
        }
    }

    private var displayMenu: some View {
        Menu {
            Button("Fit Window to Game", systemImage: "arrow.up.left.and.arrow.down.right") {
                model.fitWindowToGame()
            }
            .disabled(model.currentFrame == nil)

            Toggle(
                "Automatically Fit Game Orientation",
                isOn: $automaticallyFitGameOrientation
            )

            Divider()

            Picker("Display", selection: $displayProfileRaw) {
                ForEach(DisplayProfile.allCases) { profile in
                    Text(profile.rawValue).tag(profile.rawValue)
                }
            }
            Divider()
            Picker("LCD Motion", selection: lcdMotionSelection) {
                ForEach(LCDMotionLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .disabled(displayProfile == .purePixels)
            Divider()
            Toggle("Show Player Diagnostics", isOn: $showPlayerDiagnostics)
        } label: {
            Label(displayProfile.rawValue, systemImage: "display")
        }
        .help(displayProfile.detail)
        .accessibilityLabel("Display profile")
        .accessibilityValue(displayProfile.rawValue)
    }

    private var playerCanvasChromeColor: Color {
        if model.playerFailure != nil {
            return .red.opacity(0.72)
        }
        if model.playerVideoActivityIsDegraded || model.playerLaunchNeedsAttention {
            return .orange.opacity(0.78)
        }
        if gameplayHasFocus && model.playerIsInteractive {
            return SwanTheme.cyan.opacity(0.46)
        }
        return .white.opacity(0.16)
    }

    private var playerCanvasChromeLineWidth: CGFloat {
        model.playerFailure != nil
            || model.playerVideoActivityIsDegraded
            || model.playerLaunchNeedsAttention
            || gameplayHasFocus && model.playerIsInteractive
            ? 1.5
            : 1
    }

    private var shouldShowPlayerStatus: Bool {
        showPlayerDiagnostics
            || model.isPaused
            || model.isFastForwarding
            || model.playerStateOperation != nil
            || model.isFinalizingFailedSession
            || model.playerLaunchNeedsAttention
            || model.playerVideoActivityIsDegraded
            || model.playerIsInteractive && !gameplayHasFocus
            || prioritizedTranslationState != nil
    }

    private var playerStatus: some View {
        HStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                fullPlayerStatus
                    .fixedSize(horizontal: true, vertical: false)
                compactPlayerStatus
                    .fixedSize(horizontal: true, vertical: false)
                minimalPlayerStatus
                    .fixedSize(horizontal: true, vertical: false)
            }

            if model.playerVideoActivityIsDegraded,
               !model.playerVideoActivityNeedsAttention {
                Divider()
                    .frame(height: 16)
                Button("Recovery…", systemImage: "lifepreserver") {
                    model.presentPlayerVideoActivityDiagnostic()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
                .help("Show picture recovery actions")
                .accessibilityIdentifier("player-video-warning-review")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.84))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityIdentifier("player-runtime-status")
        .accessibilityElement(children: .contain)
    }

    private var playerInputHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundStyle(SwanTheme.cyan)
                .accessibilityHidden(true)
            Text(
                PlayerControlCopy.firstRunHint(
                    for: model.playingGame?.resolvedHardwareModel ?? .automatic
                )
            )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Button("Controls…") {
                isInputGuidePresented = true
            }
            .buttonStyle(.link)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            Button("Dismiss", systemImage: "xmark") {
                dismissCurrentPlayerInputHint()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
            .help("Dismiss controls hint")
            .accessibilityLabel("Dismiss controls hint")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.055), in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private var fullPlayerStatus: some View {
        HStack(spacing: 14) {
            runtimeStateLabel
            if model.playerIsInteractive, !gameplayHasFocus {
                keyboardFocusStatus
            }
            fullTranslationStatus
            if let controllerName = model.connectedControllerName {
                Label(controllerName, systemImage: "gamecontroller.fill")
            }
            if showPlayerDiagnostics {
                Label(displayProfile.rawValue, systemImage: "display")
                if let frame = model.currentFrame {
                    Label("Frame \(frame.number)", systemImage: "rectangle.on.rectangle")
                }
                if let savedAt = model.quickStateSavedAt {
                    Label(savedAt.formatted(date: .omitted, time: .shortened), systemImage: "clock.arrow.circlepath")
                        .help("Quick state available")
                }
            }
        }
    }

    private var compactPlayerStatus: some View {
        HStack(spacing: 12) {
            runtimeStateLabel
            if model.playerIsInteractive, !gameplayHasFocus {
                keyboardFocusStatus
            }
            prioritizedTranslationStatus
            if showPlayerDiagnostics, let frame = model.currentFrame {
                Label("Frame \(frame.number)", systemImage: "rectangle.on.rectangle")
            }
            if model.connectedControllerName != nil {
                Image(systemName: "gamecontroller.fill")
                    .accessibilityLabel("Controller connected")
                    .accessibilityValue(model.connectedControllerName ?? "Controller")
            }
        }
    }

    private var minimalPlayerStatus: some View {
        HStack(spacing: 11) {
            runtimeStateLabel
            prioritizedTranslationStatus
            if model.playerIsInteractive, !gameplayHasFocus {
                keyboardFocusStatus
            } else if showPlayerDiagnostics, let frame = model.currentFrame {
                Label("Frame \(frame.number)", systemImage: "rectangle.on.rectangle")
            }
        }
    }

    private var runtimeStateLabel: some View {
        Label(runtimeState.title, systemImage: runtimeState.symbol)
            .foregroundStyle(runtimeState.color)
            .accessibilityIdentifier(
                model.isPaused ? "player-paused-hud" : "player-runtime-state"
            )
    }

    private var keyboardFocusStatus: some View {
        Label(
            gameplayHasFocus ? "Keyboard Ready" : "Click Game for Keyboard",
            systemImage: gameplayHasFocus ? "keyboard.fill" : "keyboard.badge.ellipsis"
        )
        .foregroundStyle(gameplayHasFocus ? Color.green : Color.orange)
    }

    @ViewBuilder
    private var fullTranslationStatus: some View {
        if let role = model.activeTranslationRole {
            Label("\(role.title) · Isolated", systemImage: "character.book.closed.fill")
                .foregroundStyle(role == .original ? Color.cyan : Color.purple)
        }
        if model.translationRouteIsRecording {
            Label("Recording", systemImage: "record.circle.fill")
                .foregroundStyle(.red)
        }
        if let progress = model.translationReplayProgress,
           model.translationReplayIsActive {
            Label("Replay \(Int((progress * 100).rounded()))%", systemImage: "repeat")
                .foregroundStyle(.orange)
        }
        if let phase = model.translationComparisonPhase, phase.role != nil {
            Label(phase.title, systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.cyan)
        }
    }

    @ViewBuilder
    private var prioritizedTranslationStatus: some View {
        if let state = prioritizedTranslationState {
            Label(state.title, systemImage: state.symbol)
                .foregroundStyle(state.color)
        }
    }

    private var runtimeState: (title: String, symbol: String, color: Color) {
        if let failure = model.playerFailure {
            return (failure.statusTitle, "xmark.octagon.fill", .red)
        }
        if model.isFinalizingFailedSession {
            return ("Stopping safely…", "shield.lefthalf.filled", .orange)
        }
        if model.playerLaunchNeedsAttention {
            return (launchStageTitle, "exclamationmark.triangle.fill", .orange)
        }
        if model.playerVideoActivityIsDegraded {
            return (
                model.playerVideoActivityIssue == .lowMotion
                    ? "Picture not changing"
                    : "Picture inactive",
                "exclamationmark.triangle.fill",
                .orange
            )
        }
        if model.isLaunchingGame || model.currentFrame == nil {
            return ("Starting…", "progress.indicator", SwanTheme.cyan)
        }
        if let stateOperation = model.playerStateOperation {
            return (stateOperation.title, "clock.arrow.circlepath", SwanTheme.cyan)
        }
        if model.isPaused {
            return ("Paused", "pause.circle.fill", .orange)
        }
        if model.isFastForwarding {
            return ("Fast", "forward.fill", .orange)
        }
        return ("Playing", "play.circle.fill", .green)
    }

    private var launchHeadline: String {
        if model.playerLaunchNeedsAttention {
            switch model.playerLaunchStage ?? .verifyingGame {
            case .loadingStartupFile:
                return "Startup file is taking longer to load"
            case .startingSystem, .waitingForFirstFrame:
                return "Still waiting for the first frame"
            case .closingPreviousSession, .verifyingGame, .startingEngine, .restoringSave:
                return "\(launchStageTitle) is taking longer than expected"
            }
        }
        return "Starting \(model.playingGame?.title ?? "game")"
    }

    private var launchDetail: String {
        if model.playerLaunchNeedsAttention {
            switch model.playerLaunchStage ?? .verifyingGame {
            case .closingPreviousSession:
                return "The previous session is taking longer than expected to save and close safely. You can keep waiting or return to the Library."
            case .verifyingGame:
                return "The private game copy is taking longer than expected to verify. Try again, or return to the Library without changing the game."
            case .startingEngine:
                return "The native emulation engine is taking longer than expected to start. Try again, or return to the Library."
            case .loadingStartupFile:
                return "The installed system startup file is taking longer than expected to load. Try again or review that file in Settings."
            case .restoringSave:
                return "The local cartridge save is taking longer than expected to restore. Try again, or return to the Library without changing it."
            case .startingSystem:
                return "The emulated system has not finished powering on. Try again; if this continues, review the matching startup file."
            case .waitingForFirstFrame:
                return "The engine is running, but no game frame has arrived. Try again; if this continues, review the matching startup file."
            }
        }
        switch model.playerLaunchStage ?? .verifyingGame {
        case .closingPreviousSession:
            return "Saving the previous session and releasing the emulation hardware."
        case .verifyingGame:
            return "Confirming the private game copy before anything runs."
        case .startingEngine:
            return "Preparing the native ares emulation engine."
        case .loadingStartupFile:
            return "Loading the matching system startup file from private local storage."
        case .restoringSave:
            return "Restoring this game’s local cartridge save data."
        case .startingSystem:
            return "Powering on the emulated WonderSwan hardware."
        case .waitingForFirstFrame:
            return "The system is running and preparing its first picture."
        }
    }

    private var launchStageTitle: String {
        switch model.playerLaunchStage ?? .verifyingGame {
        case .closingPreviousSession: "Closing previous game"
        case .verifyingGame: "Verifying game"
        case .startingEngine: "Starting engine"
        case .loadingStartupFile: "Loading startup file"
        case .restoringSave: "Restoring save data"
        case .startingSystem: "Starting system"
        case .waitingForFirstFrame: "Waiting for video"
        }
    }

    private var launchStageSymbol: String {
        switch model.playerLaunchStage ?? .verifyingGame {
        case .closingPreviousSession: "arrow.backward.circle.fill"
        case .verifyingGame: "checkmark.shield.fill"
        case .startingEngine: "gearshape.2.fill"
        case .loadingStartupFile: "cpu.fill"
        case .restoringSave: "externaldrive.fill.badge.checkmark"
        case .startingSystem: "power.circle.fill"
        case .waitingForFirstFrame: "display"
        }
    }

    private var launchShowsStartupFileRecovery: Bool {
        switch model.playerLaunchStage ?? .verifyingGame {
        case .loadingStartupFile, .startingSystem, .waitingForFirstFrame:
            true
        case .closingPreviousSession, .verifyingGame, .startingEngine, .restoringSave:
            false
        }
    }

    private var launchAttentionAnnouncement: String {
        if model.playerLaunchStage == .closingPreviousSession {
            return "The previous game is taking longer than expected to close safely. Keep waiting or return to the Library."
        }
        if launchShowsStartupFileRecovery {
            return "Still waiting for the first game frame while \(launchStageTitle.lowercased()). Try again or review the matching startup file."
        }
        return "Game startup is taking longer than expected while \(launchStageTitle.lowercased()). Try again or return to the Library."
    }

    private var startupFileReplacementTitle: String {
        guard let game = model.playingGame else {
            return "Stop & Try Another Startup File…"
        }
        return "Stop & Try Another \(model.firmwareKind(for: game).title) Startup File…"
    }

    private var playerVideoActivityDetail: String {
        let startupFile = model.playingGame.map {
            " or review the \(model.firmwareKind(for: $0).title) startup file"
        } ?? ""
        switch model.playerVideoActivityIssue {
        case .lowMotion:
            return "Frames are arriving, but most of the picture is not changing. The game may simply be waiting for input. Try the controls first, then restart\(startupFile) if it remains unchanged."
        case .flatColor, .none:
            return "Frames are arriving, but the picture has stayed almost entirely one color. Try the controls first, then restart\(startupFile) if it remains unchanged."
        }
    }

    private var playerVideoActivityHeadline: String {
        model.playerVideoActivityIssue == .lowMotion
            ? "Picture is not changing"
            : "Display has stayed one color"
    }

    private var playerVideoActivityAnnouncement: String {
        switch model.playerVideoActivityIssue {
        case .lowMotion:
            "The game is producing frames, but most of the picture is not changing. Game controls remain available."
        case .flatColor, .none:
            "The game is producing frames, but the picture has stayed almost entirely one color. Game controls remain available."
        }
    }

    private var playerSurfaceAccessibilityValue: String {
        if let failure = model.playerFailure {
            let frame = model.currentFrame == nil
                ? "No game frame was produced."
                : "The last rendered frame remains visible."
            return "\(failure.accessibilityAnnouncement). \(frame)"
        }
        if model.currentFrame == nil {
            return "\(launchHeadline). \(launchStageTitle)."
        }
        let focus = gameplayHasFocus ? "Keyboard input active" : "Keyboard input inactive"
        return model.playerVideoActivityIsDegraded
            ? "\(focus). \(playerVideoActivityHeadline)."
            : focus
    }

    private var playerSurfaceAccessibilityHint: String {
        if model.playerFailure != nil {
            return "Choose a recovery action in the game display"
        }
        if model.isFinalizingFailedSession {
            return "SwanSong is saving and unloading the failed emulation session"
        }
        if model.playerVideoActivityIsDegraded {
            return "Game controls remain available. Use Recovery to review restart and BIOS options."
        }
        return "Click the game display to enable keyboard controls"
    }

    private var playerSurfaceAccessibilityActionTitle: String {
        if model.playerFailureCanRetry {
            return model.playerFailureRetryTitle
        }
        if model.playerFailure != nil {
            return model.playerFailureReturnTitle
        }
        return model.playerIsInteractive
            ? "Enable keyboard input"
            : "Emulator is stopping"
    }

    private var prioritizedTranslationState: (title: String, symbol: String, color: Color)? {
        if model.translationRouteIsRecording {
            return ("Recording", "record.circle.fill", .red)
        }
        if let progress = model.translationReplayProgress,
           model.translationReplayIsActive {
            return ("Replay \(Int((progress * 100).rounded()))%", "repeat", .orange)
        }
        if let phase = model.translationComparisonPhase, phase.role != nil {
            return (phase.title, "arrow.triangle.2.circlepath", .cyan)
        }
        if let role = model.activeTranslationRole {
            return (
                "\(role.title) · Isolated",
                "character.book.closed.fill",
                role == .original ? .cyan : .purple
            )
        }
        return nil
    }

    private var playerAspectRatio: CGFloat {
        guard let frame = model.currentFrame else { return 224.0 / 157.0 }
        return CGFloat(frame.width) / CGFloat(frame.height)
    }

    private var displayProfile: DisplayProfile {
        DisplayProfile(rawValue: displayProfileRaw) ?? .purePixels
    }

    private var lcdMotionLevel: LCDMotionLevel {
        LCDMotionLevel.nearest(to: lcdResponseScale)
    }

    private var lcdMotionSelection: Binding<LCDMotionLevel> {
        Binding(
            get: { lcdMotionLevel },
            set: { lcdResponseScale = $0.responseScale }
        )
    }

    private var translationRecordingBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                if model.translationRouteRecordingIsPreparing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    model.translationRouteRecordingIsPreparing
                        ? "STARTING CLEAN BOOT"
                        : "RECORDING ROUTE"
                )
                .font(.caption2.monospaced().weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))
                Text(
                    model.translationRouteRecordingIsPreparing
                        ? "Preparing Original with isolated save data…"
                        : "Original · Clean Boot · Frame \(model.currentFrame?.number ?? 0)"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            }

            Spacer()

            if model.translationRouteIsRecording,
               let frame = model.currentFrame {
                Button("Save at Frame \(frame.number)", systemImage: "scope") {
                    _ = model.finishTranslationRouteRecording()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: [.command, .option])
                .help("Save this exact rendered frame as the route checkpoint (Option-Command-R)")
                .accessibilityLabel("Save route test at frame \(frame.number)")
            }

            Button("Cancel", systemImage: "xmark") {
                model.cancelTranslationRouteRecording()
            }
            .buttonStyle(.bordered)
            .disabled(model.translationRouteRecordingIsPreparing)
            .help("Discard this unfinished route without saving a test case")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 920)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.red.opacity(0.34))
        }
        .accessibilityElement(children: .contain)
    }

    private func translationComparisonBanner(
        _ phase: AppModel.TranslationComparisonPhase
    ) -> some View {
        let isSuite = model.translationSuiteIsActive
        let progress = isSuite
            ? model.translationSuiteProgress
            : model.translationComparisonProgress
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.28), .purple.opacity(0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    isSuite
                        ? "A/B ROUTE SUITE · CASE \((model.translationSuiteCurrentCaseIndex ?? 0) + 1)/\(model.translationSuiteTotalCaseCount)"
                        : "A/B ROUTE VERIFICATION"
                )
                    .font(.caption2.monospaced().weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.55))
                Text(
                    isSuite
                        ? "\(model.translationSuiteCurrentCaseName ?? "Test case") · \(phase.title)"
                        : phase.title
                )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            ProgressView(value: progress ?? 0)
                .tint(.cyan)
                .frame(maxWidth: 260)

            if let progress {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 38, alignment: .trailing)
            }

            Spacer()

            Label("Deterministic controls locked", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 920)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.cyan.opacity(0.32), .purple.opacity(0.32)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    private func translationRuntimeMenu(_ role: TranslationROMRole) -> some View {
        Menu {
            if model.translationRouteIsRecording {
                Button("Save Test Case at This Frame…", systemImage: "scope") {
                    _ = model.finishTranslationRouteRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
            } else if model.translationRouteRecordingIsPreparing {
                Button("Starting Clean Boot…", systemImage: "progress.indicator") {}
                    .disabled(true)
            } else {
                Button("Restart & Record from Boot", systemImage: "record.circle") {
                    model.startTranslationRouteRecording()
                }
                .disabled(!model.canStartCleanBootRouteRecording)
            }

            Button("Replay Latest Route", systemImage: "repeat") {
                model.replayLatestTranslationRoute()
            }
            .disabled(!model.canReplayLatestTranslationRoute)
            .help(model.selectedTranslationRouteProofIssue ?? "Replay this route from a fresh clean boot")

            Divider()

            Button("Capture Translation Evidence", systemImage: "camera.viewfinder") {
                model.captureTranslationEvidence()
            }
            .disabled(
                !model.playerIsInteractive
                    || model.currentFrame == nil
                    || model.isCapturingTranslationEvidence
                    || model.translationComparisonIsActive
            )

            if model.lastTranslationEvidenceURL != nil {
                Button("Show Last Evidence", systemImage: "folder") {
                    model.revealLastTranslationEvidence()
                }
            }
        } label: {
            Label(
                model.translationRouteIsRecording
                    ? "RECORDING"
                    : model.translationComparisonIsActive
                        ? "A/B \(role.title.uppercased())"
                        : "\(role.title.uppercased()) TEST",
                systemImage: model.translationRouteIsRecording
                    ? "record.circle.fill"
                    : "character.book.closed.fill"
            )
            .font(.caption.monospaced().weight(.bold))
            .foregroundStyle(model.translationRouteIsRecording ? Color.red : Color.white.opacity(0.82))
        }
        .menuStyle(.borderlessButton)
        .help("Translation Lab runtime tools")
    }

    private func requestGameplayFocus() {
        guard model.playerIsInteractive else { return }
        Task { @MainActor in
            await Task.yield()
            gameplayHasFocus = true
        }
    }

    private var currentPlayerInputHintIsDismissed: Bool {
        model.playingGame?.resolvedHardwareModel == .pocketChallengeV2
            ? didDismissPocketChallengeV2InputHint
            : didDismissPlayerInputHint
    }

    private func dismissCurrentPlayerInputHint() {
        if model.playingGame?.resolvedHardwareModel == .pocketChallengeV2 {
            didDismissPocketChallengeV2InputHint = true
        } else {
            didDismissPlayerInputHint = true
        }
    }

    private func retryPlayerFailure() {
        awaitsRecoveryFrame = true
        model.retryPlayerFailure()
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard model.playerIsInteractive else { return .ignored }
        let commandModifiers: EventModifiers = [.command, .control, .option]
        guard press.modifiers.intersection(commandModifiers).isEmpty else {
            return .ignored
        }
        let button: EngineInput?
        if model.playingGame?.resolvedHardwareModel == .pocketChallengeV2 {
            switch press.key {
            case .upArrow, "w", "W": button = .pocketChallengeUp
            case .rightArrow, "d", "D": button = .pocketChallengeRight
            case .downArrow, "s", "S": button = .pocketChallengeDown
            case .leftArrow, "a", "A": button = .pocketChallengeLeft
            case "z", "Z": button = .pocketChallengePass
            case "x", "X": button = .pocketChallengeCircle
            case "c", "C": button = .pocketChallengeClear
            case .return: button = .pocketChallengeView
            case .escape, "e", "E": button = .pocketChallengeEscape
            default: button = nil
            }
        } else {
            switch press.key {
            case .upArrow: button = .x1
            case .rightArrow: button = .x2
            case .downArrow: button = .x3
            case .leftArrow: button = .x4
            case "w", "W": button = .y1
            case "d", "D": button = .y2
            case "s", "S": button = .y3
            case "a", "A": button = .y4
            case "z", "Z": button = .b
            case "x", "X": button = .a
            case .return: button = .start
            case "v", "V": button = .volume
            default: button = nil
            }
        }
        guard let button else { return .ignored }
        dismissCurrentPlayerInputHint()
        model.setKeyboardButton(button, pressed: !press.phase.contains(.up))
        return .handled
    }
}

struct PlayerVideoActivityRecoveryCard: View {
    static let accessibilityIdentifier = "player-video-warning"
    static let dismissAccessibilityLabel = "Dismiss picture activity notice"
    static let minimumInteractiveDimension: CGFloat = 28

    let headline: String
    let detail: String
    let startupFileAccessibilityTitle: String
    let restartIsDisabled: Bool
    let startupFileActionIsDisabled: Bool
    let onTryControls: () -> Void
    let onRestart: () -> Void
    let onReplaceStartupFile: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                summary
                    .frame(minWidth: 260, idealWidth: 360, maxWidth: .infinity)
                actions
                dismissButton
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    summary
                    Spacer(minLength: 8)
                    dismissButton
                }
                actions
            }
        }
        .padding(14)
        .frame(maxWidth: 900)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.34))
        }
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .accessibilityIdentifier(Self.accessibilityIdentifier)
        .accessibilityElement(children: .contain)
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.callout.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                tryControlsButton
                restartButton
                startupFileButton
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    tryControlsButton
                    restartButton
                }
                startupFileButton
            }
        }
    }

    private var tryControlsButton: some View {
        Button("Try Controls", systemImage: "gamecontroller.fill", action: onTryControls)
            .buttonStyle(.borderedProminent)
            .frame(minHeight: Self.minimumInteractiveDimension)
            .contentShape(Rectangle())
            .help("Keep playing and return keyboard focus to the game")
    }

    private var restartButton: some View {
        Button("Restart Game", systemImage: "arrow.clockwise", action: onRestart)
            .buttonStyle(.bordered)
            .frame(minHeight: Self.minimumInteractiveDimension)
            .contentShape(Rectangle())
            .disabled(restartIsDisabled)
    }

    private var startupFileButton: some View {
        Button(
            "Try Another Startup File…",
            systemImage: "cpu",
            action: onReplaceStartupFile
        )
        .buttonStyle(.borderless)
        .frame(minHeight: Self.minimumInteractiveDimension)
        .contentShape(Rectangle())
        .disabled(startupFileActionIsDisabled)
        .help("Stop the game, choose another startup file, and retry automatically")
        .accessibilityLabel(startupFileAccessibilityTitle)
        .accessibilityHint("Stops the current game, then retries automatically after the replacement is validated")
    }

    private var dismissButton: some View {
        Button("Dismiss", systemImage: "xmark", action: onDismiss)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(
                minWidth: Self.minimumInteractiveDimension,
                minHeight: Self.minimumInteractiveDimension
            )
            .contentShape(Rectangle())
            .help(Self.dismissAccessibilityLabel)
            .accessibilityLabel(Self.dismissAccessibilityLabel)
    }
}

private struct TranslationTestCaseNamingView: View {
    @Bindable var model: AppModel
    let onCancel: () -> Void
    let onSave: () -> Void
    let onSaveAndVerify: () -> Void
    @FocusState private var nameHasFocus: Bool

    private var trimmedName: String {
        model.translationTestCaseName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameIsValid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 120
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.cyan.opacity(0.2), .purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "scope")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Name This Test Case")
                        .font(.title2.weight(.semibold))
                    Text(
                        "The clean-boot route is saved at frame \(model.latestTranslationRoute?.targetFrameNumber ?? model.latestTranslationRoute?.totalFrames ?? 0). Give reviewers one clear thing to check."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                provenanceBadge("Original", symbol: "shippingbox.fill", color: .cyan)
                provenanceBadge("Clean Boot", symbol: "power.circle.fill", color: .green)
                provenanceBadge("Isolated Save", symbol: "lock.fill", color: .purple)
                provenanceBadge(
                    "Frame \(model.latestTranslationRoute?.targetFrameNumber ?? model.latestTranslationRoute?.totalFrames ?? 0)",
                    symbol: "scope",
                    color: .orange
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Name")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(model.translationTestCaseName.count) / 120")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(
                            model.translationTestCaseName.count > 120 ? Color.red : Color.secondary
                        )
                }
                TextField("Chapter 2 shop overflow", text: $model.translationTestCaseName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameHasFocus)
                    .accessibilityLabel("Test case name")
                if trimmedName.isEmpty {
                    Text("Enter a short name for this checkpoint.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if trimmedName.count > 120 {
                    Text("Shorten the name to 120 characters or fewer.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("What should a reviewer check?")
                        .font(.caption.weight(.semibold))
                    Text("Optional")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(model.translationTestCaseNote.count) / 4,000")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(
                            model.translationTestCaseNote.count > 4_000 ? Color.red : Color.secondary
                        )
                }
                TextEditor(text: $model.translationTestCaseNote)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(minHeight: 88, maxHeight: 118)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.separator.opacity(0.6))
                    }
                    .accessibilityLabel("Test case review note")
            }

            Divider()

            HStack {
                Label("The route is immutable; this name and note can be edited later.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Name Later", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!nameIsValid || model.translationTestCaseNote.count > 4_000)
                Button("Save & Verify Both", systemImage: "checkmark.arrow.trianglehead.counterclockwise", action: onSaveAndVerify)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!nameIsValid || model.translationTestCaseNote.count > 4_000)
            }
        }
        .padding(24)
        .frame(width: 680)
        .onAppear { nameHasFocus = true }
    }

    private func provenanceBadge(
        _ title: String,
        symbol: String,
        color: Color
    ) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private struct InputGuideView: View {
    @Environment(\.openSettings) private var openSettings
    let controllerName: String?
    let activeInput: EngineInput
    let controllerProfile: ControllerProfile
    let hardwareModel: EngineHardwareModel

    var body: some View {
        if hardwareModel == .pocketChallengeV2 {
            PocketChallengeInputGuideView(
                controllerName: controllerName,
                activeInput: activeInput
            )
        } else {
            VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WonderSwan Controls")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Two direction clusters are part of the original hardware.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(
                    controllerName ?? "Keyboard",
                    systemImage: controllerName == nil ? "keyboard" : "gamecontroller.fill"
                )
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
            }

            HStack(alignment: .top, spacing: 18) {
                InputClusterView(
                    title: "X Cluster",
                    subtitle: "Arrow keys · \(controllerProfile.preset.title)",
                    top: ("X1", "↑ · \(binding(.x1))", .x1),
                    right: ("X2", "→ · \(binding(.x2))", .x2),
                    bottom: ("X3", "↓ · \(binding(.x3))", .x3),
                    left: ("X4", "← · \(binding(.x4))", .x4),
                    activeInput: activeInput
                )
                InputClusterView(
                    title: "Y Cluster",
                    subtitle: "WASD · \(controllerProfile.preset.title)",
                    top: ("Y1", "W · \(binding(.y1))", .y1),
                    right: ("Y2", "D · \(binding(.y2))", .y2),
                    bottom: ("Y3", "S · \(binding(.y3))", .y3),
                    left: ("Y4", "A · \(binding(.y4))", .y4),
                    activeInput: activeInput
                )
                ActionInputView(activeInput: activeInput, controllerProfile: controllerProfile)
            }

            HStack {
                Label("Inputs light up live while you play.", systemImage: "waveform.path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Paused: ⌥⌘→ advances one frame", systemImage: "forward.frame")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Configure Controller…", systemImage: "slider.horizontal.3") {
                    UserDefaults.standard.set(1, forKey: "settingsPane")
                    openSettings()
                }
            }
        }
            .padding(22)
            .frame(width: 760)
        }
    }

    private func binding(_ control: WonderSwanControl) -> String {
        controllerProfile.element(for: control)?.shortTitle ?? "—"
    }
}

private struct PocketChallengeInputGuideView: View {
    let controllerName: String?
    let activeInput: EngineInput

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pocket Challenge V2 Controls")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("The Benesse keypad is mapped directly—no WonderSwan cluster aliases.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(
                    controllerName ?? "Keyboard",
                    systemImage: controllerName == nil ? "keyboard" : "gamecontroller.fill"
                )
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
            }

            HStack(alignment: .top, spacing: 18) {
                InputClusterView(
                    title: "Direction Pad",
                    subtitle: "Arrows or WASD · D-pad or stick",
                    top: ("Up", "↑ / W", .pocketChallengeUp),
                    right: ("Right", "→ / D", .pocketChallengeRight),
                    bottom: ("Down", "↓ / S", .pocketChallengeDown),
                    left: ("Left", "← / A", .pocketChallengeLeft),
                    activeInput: activeInput
                )
                PocketChallengeActionInputView(activeInput: activeInput)
            }

            Label(
                "Controller: west Pass · south Circle · east Clear · Menu View · north/Options Escape",
                systemImage: "gamecontroller"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 620)
    }
}

private struct PocketChallengeActionInputView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let activeInput: EngineInput

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Keypad")
                .font(.headline)
            action("Pass", detail: "Z · west face", input: .pocketChallengePass)
            action("Circle", detail: "X · south face", input: .pocketChallengeCircle)
            action("Clear", detail: "C · east face", input: .pocketChallengeClear)
            action("View", detail: "Return · Menu", input: .pocketChallengeView)
            action("Escape", detail: "Esc / E · north or Options", input: .pocketChallengeEscape)
        }
        .padding(14)
        .frame(width: 300)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func action(_ label: String, detail: String, input: EngineInput) -> some View {
        let pressed = activeInput.contains(input)
        return HStack(spacing: 9) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(pressed ? Color.white : Color.primary)
                .frame(width: 58, height: 30)
                .background(
                    pressed ? Color.accentColor : Color.primary.opacity(0.08),
                    in: Capsule()
                )
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: pressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(detail)")
        .accessibilityValue(pressed ? "Pressed" : "Not pressed")
    }
}

private struct InputClusterView: View {
    typealias Direction = (label: String, key: String, input: EngineInput)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let subtitle: String
    let top: Direction
    let right: Direction
    let bottom: Direction
    let left: Direction
    let activeInput: EngineInput

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 4) {
                inputButton(top)
                HStack(spacing: 32) {
                    inputButton(left)
                    inputButton(right)
                }
                inputButton(bottom)
            }
        }
        .padding(14)
        .frame(width: 220)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func inputButton(_ direction: Direction) -> some View {
        let pressed = activeInput.contains(direction.input)
        return VStack(spacing: 1) {
            Text(direction.label)
                .font(.caption2.monospaced().weight(.bold))
            Text(direction.key)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .foregroundStyle(pressed ? Color.white : Color.primary)
        .frame(width: 60, height: 40)
        .background(
            pressed ? Color.accentColor : Color.primary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: pressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(direction.label), \(direction.key)")
        .accessibilityValue(pressed ? "Pressed" : "Not pressed")
    }
}

private struct ActionInputView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let activeInput: EngineInput
    let controllerProfile: ControllerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.headline)
            action("A", detail: "X · \(binding(.a))", input: .a)
            action("B", detail: "Z · \(binding(.b))", input: .b)
            action("Start", detail: "Return · \(binding(.start))", input: .start)
            action("Volume", detail: "V · \(binding(.volume))", input: .volume)
        }
        .padding(14)
        .frame(width: 220)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func action(_ label: String, detail: String, input: EngineInput) -> some View {
        let pressed = activeInput.contains(input)
        return HStack(spacing: 9) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(pressed ? Color.white : Color.primary)
                .frame(width: 48, height: 30)
                .background(
                    pressed ? Color.accentColor : Color.primary.opacity(0.08),
                    in: Capsule()
                )
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: pressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(detail)")
        .accessibilityValue(pressed ? "Pressed" : "Not pressed")
    }

    private func binding(_ control: WonderSwanControl) -> String {
        controllerProfile.element(for: control)?.shortTitle ?? "—"
    }
}

@MainActor
final class StateTimelineGeometryProbe {
    static let coordinateSpace = "state-timeline-scroll-viewport"

    private(set) var viewportFrame = CGRect.zero
    private(set) var actionFrames: [String: CGRect] = [:]

    func recordViewport(_ frame: CGRect) {
        viewportFrame = frame
    }

    func recordAction(identifier: String, frame: CGRect) {
        actionFrames[identifier] = frame
    }
}

private struct StateTimelineViewportGeometryReader: View {
    let probe: StateTimelineGeometryProbe?

    var body: some View {
        GeometryReader { proxy in
            let frame = CGRect(origin: .zero, size: proxy.size)
            Color.clear
                .onAppear { probe?.recordViewport(frame) }
                .onChange(of: frame) { _, value in probe?.recordViewport(value) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StateTimelineActionGeometryReader: View {
    let identifier: String
    let probe: StateTimelineGeometryProbe?

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(
                in: .named(StateTimelineGeometryProbe.coordinateSpace)
            )
            Color.clear
                .onAppear { probe?.recordAction(identifier: identifier, frame: frame) }
                .onChange(of: frame) { _, value in
                    probe?.recordAction(identifier: identifier, frame: value)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct StateTimelineView: View {
    static let accessibilityIdentifier = "state-timeline"
    static let minimumInteractiveDimension: CGFloat = 28

    @Bindable var model: AppModel
    var geometryProbe: StateTimelineGeometryProbe? = nil
    @State private var pendingDeletion: GameStateSummary?
    @AccessibilityFocusState private var focusedStateID: GameStateSummary.ID?
    @AccessibilityFocusState private var captureHasAccessibilityFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Save-State Timeline")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(model.playingGame?.title ?? "WonderSwan") · Keeps the 12 most recent states on this Mac")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save Current Moment", systemImage: "square.and.arrow.down") {
                    model.saveQuickState()
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: Self.minimumInteractiveDimension)
                .contentShape(Rectangle())
                .disabled(model.playerStateOperationIsBusy)
                .help(
                    model.timelineStates.count >= 12
                        ? "Saves this moment and removes the oldest state from the timeline"
                        : "Saves the current game moment to this private timeline"
                )
                .accessibilityFocused($captureHasAccessibilityFocus)
                .accessibilityIdentifier("state-capture")
                if let operation = model.playerStateOperation {
                    ProgressView()
                        .controlSize(.small)
                        .help(operation.title)
                        .accessibilityLabel(operation.title)
                        .accessibilityIdentifier("state-operation")
                }
                Button("Done") {
                    model.dismissStateTimeline()
                }
                .keyboardShortcut(.cancelAction)
                .frame(minHeight: Self.minimumInteractiveDimension)
                .contentShape(Rectangle())
                .disabled(model.playerStateOperationIsBusy)
            }

            if !model.timelineStates.isEmpty {
                Text(timelineSummary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(timelineSummary)
            }

            if model.timelineStates.isEmpty {
                ContentUnavailableView(
                    "No Saved Moments",
                    systemImage: "clock.badge.questionmark",
                    description: Text("Save the current moment to begin this game’s private visual timeline.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { viewport in
                    ScrollView([.horizontal, .vertical]) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(model.timelineStates) { state in
                                StateTimelineCard(
                                    state: state,
                                    isQuickState: state.isQuickState,
                                    isBusy: model.playerStateOperationIsBusy,
                                    onLoad: { model.loadTimelineState(state.id) },
                                    onDelete: { pendingDeletion = state },
                                    geometryProbe: geometryProbe
                                )
                                .accessibilityFocused($focusedStateID, equals: state.id)
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(
                            minWidth: viewport.size.width,
                            minHeight: viewport.size.height,
                            alignment: .topLeading
                        )
                    }
                    .scrollIndicators(.visible)
                    .coordinateSpace(name: StateTimelineGeometryProbe.coordinateSpace)
                    .background(StateTimelineViewportGeometryReader(probe: geometryProbe))
                }
            }
        }
        .padding(24)
        .background(.regularMaterial)
        .accessibilityIdentifier(Self.accessibilityIdentifier)
        .alert(
            "Delete Saved State?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            Button("Delete State", role: .destructive) {
                deletePendingState()
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text(deletionMessage)
        }
    }

    private var timelineSummary: String {
        let ready = model.timelineStates.count {
            $0.compatibility.isReady && $0.previewIssue == nil
        }
        let unavailable = model.timelineStates.count - ready
        let readyText = "\(ready) ready"
        let unavailableText = unavailable == 0 ? nil : "\(unavailable) unavailable"
        return ([readyText, unavailableText].compactMap { $0 } + ["newest first"])
            .joined(separator: " · ")
    }

    private var deletionMessage: String {
        guard let pendingDeletion else { return "This saved state will be permanently removed." }
        let date = pendingDeletion.manifest.createdAt.formatted(
            date: .abbreviated,
            time: .shortened
        )
        let quickNote = pendingDeletion.isQuickState
            ? " The newest remaining state will become Quick Load."
            : ""
        return "The state from \(date) will be permanently removed. This can’t be undone.\(quickNote)"
    }

    private func deletePendingState() {
        guard let pendingDeletion,
              let deletedIndex = model.timelineStates.firstIndex(where: {
                  $0.id == pendingDeletion.id
              }) else { return }
        let deletedID = pendingDeletion.id
        model.deleteTimelineState(deletedID)
        self.pendingDeletion = nil
        guard !model.timelineStates.contains(where: { $0.id == deletedID }) else { return }

        postAccessibilityAnnouncement("Saved state deleted.", priority: .high)
        let nextState: GameStateSummary? = if model.timelineStates.indices.contains(deletedIndex) {
            model.timelineStates[deletedIndex]
        } else {
            model.timelineStates.last
        }
        Task { @MainActor in
            await Task.yield()
            if let nextState {
                captureHasAccessibilityFocus = false
                focusedStateID = nextState.id
            } else {
                focusedStateID = nil
                captureHasAccessibilityFocus = true
            }
        }
    }
}

struct StateTimelineCard: View {
    static let minimumInteractiveDimension: CGFloat = 28

    let state: GameStateSummary
    let isQuickState: Bool
    let isBusy: Bool
    let onLoad: () -> Void
    let onDelete: () -> Void
    var geometryProbe: StateTimelineGeometryProbe? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                Group {
                    if state.previewIssue == nil,
                       let image = NSImage(data: state.previewPNG) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .accessibilityLabel("Saved-game preview, frame \(state.manifest.frameNumber)")
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            Text(previewFallbackTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(previewFallbackDetail)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(previewFallbackTitle). \(previewFallbackDetail).")
                    }
                }
                .frame(width: 232, height: 154)
                .background(.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                compatibilityBadge
                    .padding(8)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(friendlyDate)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .help(state.manifest.createdAt.formatted(date: .complete, time: .standard))
                Spacer(minLength: 4)
                if isQuickState {
                    Label {
                        Text(isLoadable ? "Quick Load" : "Quick State")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: isLoadable ? "bolt.fill" : "bolt.slash.fill")
                            .foregroundStyle(isLoadable ? SwanTheme.cyan : Color.orange)
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(
                                (isLoadable ? SwanTheme.cyan : Color.orange).opacity(0.34),
                                lineWidth: 1
                            )
                    }
                    .fixedSize()
                }
            }
            HStack {
                Text("Frame \(state.manifest.frameNumber)")
                Spacer()
                Text(ByteCountFormatter.string(
                    fromByteCount: Int64(state.manifest.stateByteCount),
                    countStyle: .file
                ))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Text(compatibilityDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 45, alignment: .topLeading)

            HStack {
                Button(loadButtonTitle, systemImage: loadButtonSymbol, action: onLoad)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: Self.minimumInteractiveDimension)
                    .contentShape(Rectangle())
                    .disabled(isBusy || !isLoadable)
                    .help(loadButtonHelp)
                    .accessibilityLabel("\(loadButtonTitle), state from \(friendlyDate), frame \(state.manifest.frameNumber)")
                    .accessibilityHint(loadButtonHelp)
                    .accessibilityIdentifier("state-load-\(state.id.uuidString.lowercased())")
                    .background(
                        StateTimelineActionGeometryReader(
                            identifier: "state-load-\(state.id.uuidString.lowercased())",
                            probe: geometryProbe
                        )
                    )
                Spacer()
                Button("Delete State", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
                    .frame(
                        minWidth: Self.minimumInteractiveDimension,
                        minHeight: Self.minimumInteractiveDimension
                    )
                    .contentShape(Rectangle())
                    .disabled(isBusy)
                    .help("Delete this saved state…")
                    .accessibilityLabel("Delete state from \(friendlyDate), frame \(state.manifest.frameNumber)")
                    .accessibilityIdentifier("state-delete-\(state.id.uuidString.lowercased())")
                    .background(
                        StateTimelineActionGeometryReader(
                            identifier: "state-delete-\(state.id.uuidString.lowercased())",
                            probe: geometryProbe
                        )
                    )
            }
        }
        .padding(12)
        .frame(width: 256)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(compatibilityColor.opacity(0.42), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityContractLabel)
        .accessibilityIdentifier("state-card-\(state.id.uuidString.lowercased())")
    }

    private var friendlyDate: String {
        if Calendar.current.isDateInToday(state.manifest.createdAt) {
            return "Today, \(state.manifest.createdAt.formatted(date: .omitted, time: .shortened))"
        }
        if Calendar.current.isDateInYesterday(state.manifest.createdAt) {
            return "Yesterday, \(state.manifest.createdAt.formatted(date: .omitted, time: .shortened))"
        }
        return state.manifest.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var accessibilityContractLabel: String {
        "Saved state from \(friendlyDate), frame \(state.manifest.frameNumber), \(compatibilityTitle)"
    }

    private var compatibilityBadge: some View {
        Label {
            Text(compatibilityTitle)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: compatibilitySymbol)
                .foregroundStyle(compatibilityColor)
        }
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(.thickMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(compatibilityColor.opacity(0.46), lineWidth: 1)
            }
            .accessibilityLabel("State availability: \(compatibilityTitle)")
            .accessibilityValue(compatibilityDetail)
    }

    private var compatibilityTitle: String {
        if state.previewIssue != nil {
            return "Preview Missing/Damaged"
        }
        return switch state.compatibility {
        case .ready: "Ready"
        case .legacyNeedsConfirmation: "Legacy"
        case .wrongROM: "Different Game File"
        case .wrongFirmware: "Different Startup File"
        case .wrongEngineBuild: "Incompatible Engine"
        case .damaged: "Damaged"
        }
    }

    private var compatibilitySymbol: String {
        if state.previewIssue != nil {
            return "photo.badge.exclamationmark"
        }
        return switch state.compatibility {
        case .ready: "checkmark.circle.fill"
        case .legacyNeedsConfirmation: "clock.badge.exclamationmark"
        case .wrongROM: "shippingbox.and.arrow.backward"
        case .wrongFirmware: "cpu"
        case .wrongEngineBuild: "gearshape.2"
        case .damaged: "exclamationmark.octagon.fill"
        }
    }

    private var compatibilityColor: Color {
        if state.previewIssue != nil {
            return .red
        }
        return switch state.compatibility {
        case .ready: .green
        case .legacyNeedsConfirmation, .wrongROM, .wrongFirmware: .orange
        case .wrongEngineBuild: SwanTheme.violet
        case .damaged: .red
        }
    }

    private var compatibilityDetail: String {
        if state.previewIssue != nil {
            return "The saved preview is damaged or missing, so SwanSong won’t load this state. Delete it and save a new moment to replace it."
        }
        return switch state.compatibility {
        case .ready:
            "Compatible with this game, startup file, and emulation engine."
        case .legacyNeedsConfirmation:
            "Created by an earlier SwanSong version and missing full compatibility information."
        case let .wrongROM(reason),
             let .wrongFirmware(reason),
             let .wrongEngineBuild(reason),
             let .damaged(reason):
            reason
        }
    }

    private var loadButtonTitle: String {
        isLoadable ? "Load State" : "Can’t Load"
    }

    private var loadButtonSymbol: String {
        isLoadable ? "clock.arrow.circlepath" : "lock.fill"
    }

    private var loadButtonHelp: String {
        isLoadable
            ? "Replaces the current game state after creating a rollback point. Undo will be available."
            : compatibilityDetail
    }

    private var isLoadable: Bool {
        state.compatibility.isReady && state.previewIssue == nil
    }

    private var previewFallbackTitle: String {
        if state.previewIssue != nil {
            return "Preview Damaged or Missing"
        }
        return "No Preview Saved"
    }

    private var previewFallbackDetail: String {
        if state.previewIssue != nil {
            return "This state can’t be loaded safely"
        }
        return state.compatibility.isReady
            ? "State is still ready to load"
            : "See availability below"
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("automaticallyFitGameOrientation") private var automaticallyFitGameOrientation = true
    @AppStorage("settingsPane") private var selectedTab = 0
    @AppStorage("displayProfile") private var displayProfileRaw = DisplayProfile.purePixels.rawValue
    @AppStorage("lcdResponseScale") private var lcdResponseScale = 1.0
    @AppStorage("pauseWhenInactive") private var pauseWhenInactive = true
    private let backendName = (try? EngineSession().backendName) ?? "Unavailable"

    var body: some View {
        TabView(selection: $selectedTab) {
            Form {
                Section {
                    HStack(spacing: 14) {
                        SwanSongIcon(size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("SwanSong")
                                .font(.title3.weight(.semibold))
                            Text("A focused WonderSwan player and translation studio for macOS.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                Section("Screen") {
                    Picker("Display", selection: $displayProfileRaw) {
                        ForEach(DisplayProfile.allCases) { profile in
                            Text(profile.rawValue).tag(profile.rawValue)
                        }
                    }
                    Text(displayProfile.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("LCD motion response", selection: lcdMotionSelection) {
                        ForEach(LCDMotionLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(displayProfile == .purePixels)
                }
                Section("Player") {
                    Toggle(
                        "Automatically fit horizontal and vertical games",
                        isOn: $automaticallyFitGameOrientation
                    )
                    Toggle("Pause when SwanSong is in the background", isOn: $pauseWhenInactive)
                    LabeledContent("Execution engine", value: backendName)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
            .tabItem {
                Label("Display & Player", systemImage: "display")
            }
            .tag(0)

            ControllerSettingsView(model: model)
                .tabItem {
                    Label("Controller", systemImage: "gamecontroller.fill")
                }
                .tag(1)

            FirmwareSettingsView(model: model)
                .tabItem {
                    Label("Startup Files", systemImage: "cpu")
                }
                .tag(2)

        }
        .tint(SwanTheme.accent)
        .background(SwanTheme.libraryBackground.ignoresSafeArea())
        .onAppear {
            if ProcessInfo.processInfo.environment["SWAN_SONG_SETTINGS_TAB"] == "controller" {
                selectedTab = 1
            } else if ProcessInfo.processInfo.environment["SWAN_SONG_SETTINGS_TAB"] == "firmware" {
                selectedTab = 2
            }
        }
    }

    private var displayProfile: DisplayProfile {
        DisplayProfile(rawValue: displayProfileRaw) ?? .purePixels
    }

    private var lcdMotionSelection: Binding<LCDMotionLevel> {
        Binding(
            get: { LCDMotionLevel.nearest(to: lcdResponseScale) },
            set: { lcdResponseScale = $0.responseScale }
        )
    }
}

private struct FirmwareSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: AppModel
    @State private var removalCandidate: WonderSwanFirmwareKind?
    @State private var pendingFocusKind: WonderSwanFirmwareKind?
    @State private var targetedFirmwareKind: WonderSwanFirmwareKind?
    @State private var showsAdvanced = false
    @State private var showsStartupFileGuide = false
    @FocusState private var focusedFirmwareKind: WonderSwanFirmwareKind?
    @AccessibilityFocusState private var accessibilityFocusedFirmwareKind: WonderSwanFirmwareKind?
    @AccessibilityFocusState private var feedbackHasAccessibilityFocus: Bool

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [SwanTheme.violet, SwanTheme.cyan.opacity(0.82)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 58, height: 58)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Startup Files")
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Add your own startup file once for each system in your library.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Label(
                        libraryReadiness.summary,
                        systemImage: libraryReadiness.summarySymbol
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readinessSummaryColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        readinessSummaryColor.opacity(0.1),
                        in: Capsule()
                    )
                    .accessibilityLabel(libraryReadiness.summary)
                }
                .padding(.vertical, 3)
            }

            if model.firmwareSettingsIsBusy
                || model.firmwareSettingsError != nil
                || model.firmwareSettingsNotice != nil {
                Section("Setup Status") {
                    settingsFeedback
                }
            }

            Section("Systems") {
                firmwareRow(.monochrome)
                firmwareRow(.color)
                firmwareRow(.pocketChallengeV2)
            }

            Section("Help") {
                Button("About Startup Files…", systemImage: "questionmark.circle") {
                    showsStartupFileGuide = true
                }
                Text("Validation and storage stay on this Mac. SwanSong never downloads or shares these files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("WonderSwan file size", value: "4 KiB")
                        LabeledContent("WonderSwan Color file size", value: "8 KiB")
                        LabeledContent("Pocket Challenge V2 file size", value: "4 KiB")

                        Divider()

                        Text("Files are checked before SwanSong stores private local copies in Application Support. ZIP archives must contain exactly one valid startup file.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Show Storage Folder", systemImage: "folder") {
                            model.revealFirmwareFolder()
                        }
                        .disabled(model.firmwareImportIsBusy)
                    }
                }
            } footer: {
                Text("Use startup files copied from hardware you own or another source you are authorized to use. SwanSong never includes or downloads them.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .accessibilityIdentifier(SettingsSurfaceAccessibility.startupFiles)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: model.firmwareSettingsError
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: model.firmwareSettingsNotice
        )
        .alert(
            removalCandidate.map { "Remove \($0.title) Startup File?" }
                ?? "Remove Startup File?",
            isPresented: Binding(
                get: { removalCandidate != nil },
                set: { if !$0 { removalCandidate = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                removalCandidate = nil
            }
            .keyboardShortcut(.defaultAction)

            if let kind = removalCandidate {
                Button("Remove", role: .destructive) {
                    removalCandidate = nil
                    model.removeFirmwareFromSettings(kind)
                }
            }
        } message: {
            if let kind = removalCandidate {
                Text("Games for \(kind.title) will stop launching until this startup file is added again. The original file outside SwanSong is not changed.")
            }
        }
        .onChange(of: model.firmwareSettingsNotice) { _, notice in
            guard let notice else { return }
            postAccessibilityAnnouncement(notice, priority: .high)
            restoreFirmwareActionFocus()
        }
        .onChange(of: model.firmwareSettingsError) { _, error in
            guard let error else { return }
            postAccessibilityAnnouncement("Startup file error. \(error)", priority: .high)
            feedbackHasAccessibilityFocus = true
            restoreFirmwareActionFocus(accessibility: false)
        }
        .onChange(of: model.firmwareSettingsIsBusy) { _, isBusy in
            guard isBusy else { return }
            postAccessibilityAnnouncement("Checking and installing the startup file.")
        }
        .sheet(isPresented: $showsStartupFileGuide) {
            StartupFileGuideView()
        }
    }

    private func firmwareRow(_ kind: WonderSwanFirmwareKind) -> some View {
        let installed = model.isFirmwareInstalled(kind)
        let rowReadiness = libraryReadiness.rowReadiness(for: kind)
        let rowColor = readinessColor(for: rowReadiness)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: rowReadiness == .ready ? "checkmark.seal.fill" : rowReadiness.symbol)
                    .font(.title3)
                    .foregroundStyle(rowColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.body.weight(.semibold))
                    Text(systemDescription(for: kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Label(
                    rowReadiness.title,
                    systemImage: rowReadiness.symbol
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(rowColor)
                .accessibilityLabel(
                    "\(kind.title), \(rowReadiness.title.lowercased())"
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    firmwareDropSummary(kind, installed: installed)
                    Spacer(minLength: 12)
                    firmwareActions(kind, installed: installed, readiness: rowReadiness)
                }

                VStack(alignment: .leading, spacing: 9) {
                    firmwareDropSummary(kind, installed: installed)
                    firmwareActions(kind, installed: installed, readiness: rowReadiness)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(
            targetedFirmwareKind == kind
                ? SwanTheme.accent.opacity(0.10)
                : rowColor.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    targetedFirmwareKind == kind
                        ? SwanTheme.cyan.opacity(0.7)
                        : Color.clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("firmware-settings-\(kind.rawValue)-row")
        .dropDestination(for: URL.self) { urls, _ in
            guard
                !model.firmwareImportIsBusy,
                !model.isPlaying,
                let url = urls.first,
                urls.count == 1
            else { return false }
            pendingFocusKind = kind
            model.installFirmwareFromSettings(at: url, requiredKind: kind)
            return true
        } isTargeted: { targeted in
            targetedFirmwareKind = targeted ? kind : nil
        }
        .animation(.easeInOut(duration: 0.14), value: targetedFirmwareKind)
    }

    private func firmwareDropSummary(
        _ kind: WonderSwanFirmwareKind,
        installed: Bool
    ) -> some View {
        Label(
            targetedFirmwareKind == kind
                ? "Release to validate"
                : "\(kind.expectedByteCount / 1_024) KiB · Drop to \(installed ? "replace" : "add")",
            systemImage: targetedFirmwareKind == kind
                ? "arrow.down.circle.fill"
                : "arrow.down.doc"
        )
        .font(.caption)
        .foregroundStyle(
            targetedFirmwareKind == kind ? SwanTheme.accent : Color.secondary
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func firmwareActions(
        _ kind: WonderSwanFirmwareKind,
        installed: Bool,
        readiness: StartupFileRowReadiness
    ) -> some View {
        HStack(spacing: 8) {
            if !installed && readiness == .neededForLibrary {
                firmwareChooseButton(kind, installed: installed)
                    .buttonStyle(.borderedProminent)
            } else {
                firmwareChooseButton(kind, installed: installed)
                    .buttonStyle(.bordered)
            }

            if installed {
                Menu {
                    Button("Remove Startup File…", systemImage: "trash", role: .destructive) {
                        removalCandidate = kind
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(
                            minWidth: SettingsSurfaceAccessibility.minimumInteractiveDimension,
                            minHeight: SettingsSurfaceAccessibility.minimumInteractiveDimension
                        )
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .disabled(model.firmwareImportIsBusy || model.isPlaying)
                .help("More actions for \(kind.title)")
                .accessibilityLabel("More actions for \(kind.title) startup file")
            }
        }
    }

    private func firmwareChooseButton(
        _ kind: WonderSwanFirmwareKind,
        installed: Bool
    ) -> some View {
        Button(installed ? "Replace…" : "Add…") {
            pendingFocusKind = kind
            model.chooseFirmwareFromSettings(for: kind)
        }
        .frame(minHeight: SettingsSurfaceAccessibility.minimumInteractiveDimension)
        .disabled(model.firmwareImportIsBusy || model.isPlaying)
        .focused($focusedFirmwareKind, equals: kind)
        .accessibilityFocused($accessibilityFocusedFirmwareKind, equals: kind)
        .accessibilityLabel(
            "\(installed ? "Replace" : "Add") \(kind.title) startup file"
        )
    }

    @ViewBuilder
    private var settingsFeedback: some View {
        Group {
            if model.firmwareSettingsIsBusy {
                HStack(spacing: 11) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Checking startup file…")
                            .font(.callout.weight(.semibold))
                        Text("SwanSong is validating the selected system and saving a private local copy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            } else if let error = model.firmwareSettingsError {
                feedbackRow(
                    error,
                    symbol: "exclamationmark.triangle.fill",
                    color: .red
                ) {
                    model.firmwareSettingsError = nil
                }
            } else if let notice = model.firmwareSettingsNotice {
                feedbackRow(
                    notice,
                    symbol: "checkmark.circle.fill",
                    color: .green
                ) {
                    model.firmwareSettingsNotice = nil
                }
            }
        }
        .accessibilityFocused($feedbackHasAccessibilityFocus)
    }

    private func feedbackRow(
        _ message: String,
        symbol: String,
        color: Color,
        onDismiss: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss setup status")
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .transition(
            reduceMotion
                ? .opacity
                : .move(edge: .top).combined(with: .opacity)
        )
    }

    private var libraryReadiness: StartupFileLibraryReadiness {
        StartupFileLibraryReadiness(
            requiredKinds: model.startupFileKindsRequiredByLibrary,
            installedKinds: Set(
                WonderSwanFirmwareKind.allCases.filter {
                    model.isFirmwareInstalled($0)
                }
            )
        )
    }

    private var readinessSummaryColor: Color {
        if libraryReadiness.needsAttention { return .orange }
        if libraryReadiness.isReadyForLibrary { return .green }
        return .secondary
    }

    private func readinessColor(for readiness: StartupFileRowReadiness) -> Color {
        switch readiness {
        case .ready: .green
        case .neededForLibrary: .orange
        case .notInstalled: .secondary
        }
    }

    private func restoreFirmwareActionFocus(accessibility: Bool = true) {
        guard let kind = pendingFocusKind else { return }
        pendingFocusKind = nil
        Task { @MainActor in
            await Task.yield()
            focusedFirmwareKind = kind
            if accessibility {
                accessibilityFocusedFirmwareKind = kind
            }
        }
    }

    private func systemDescription(for kind: WonderSwanFirmwareKind) -> String {
        switch kind {
        case .monochrome:
            "Starts original monochrome WonderSwan games."
        case .color:
            "Starts WonderSwan Color and SwanCrystal games."
        case .pocketChallengeV2:
            "Starts Pocket Challenge V2 software with its Benesse keypad and KARNAK cartridge hardware."
        }
    }
}

private struct ControllerSettingsView: View {
    @Bindable var model: AppModel
    @State private var showsLiveInputTest = false

    private var presetSelection: Binding<ControllerMappingPreset> {
        Binding(
            get: { model.controllerProfile.preset },
            set: { model.applyControllerPreset($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        controllerHeader
                        Spacer(minLength: 16)
                        connectionStatus
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        controllerHeader
                        connectionStatus
                    }
                }

                GroupBox("Mapping Layout") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            presetPicker
                            Text(model.controllerProfile.preset.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            restoreDefaultButton
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                presetPicker
                                Spacer()
                                restoreDefaultButton
                            }
                            Text(model.controllerProfile.preset.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)
                }

                mappingDeck

                if let learning = model.controllerLearningControl {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Press any controller control for \(learning.title)")
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Button("Cancel", action: model.cancelLearningControllerBinding)
                            .frame(
                                minHeight: SettingsSurfaceAccessibility.minimumInteractiveDimension
                            )
                    }
                    .padding(12)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Label(
                        "Choose a WonderSwan tile, then press the physical control. Its menu also supports manual selection and clearing.",
                        systemImage: "hand.tap"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                DisclosureGroup(isExpanded: $showsLiveInputTest) {
                    ControllerLiveInputView(model: model)
                        .padding(.top, 8)
                } label: {
                    HStack {
                        Label("Live Input Test", systemImage: "waveform.path.ecg")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(model.connectedControllerName == nil ? "Waiting" : "Listening")
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(model.connectedControllerName == nil ? Color.secondary : Color.green)
                    }
                }
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier(SettingsSurfaceAccessibility.controllerLiveInput)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier(SettingsSurfaceAccessibility.controllerMapping)
    }

    private var controllerHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .cyan.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("WonderSwan Controller")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Map both direction clusters as native WonderSwan controls.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionStatus: some View {
        Label(
            model.connectedControllerName ?? "No controller connected",
            systemImage: model.connectedControllerName == nil
                ? "gamecontroller"
                : "checkmark.circle.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(model.connectedControllerName == nil ? Color.secondary : Color.green)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
        .accessibilityLabel("Controller connection")
        .accessibilityValue(model.connectedControllerName ?? "No controller connected")
    }

    private var presetPicker: some View {
        Picker("Layout", selection: presetSelection) {
            ForEach(ControllerMappingPreset.allCases) { preset in
                Text(preset.title)
                    .tag(preset)
                    .disabled(preset == .custom)
            }
        }
        .frame(minWidth: 220, idealWidth: 280, maxWidth: 300)
    }

    private var restoreDefaultButton: some View {
        Button("Restore Default", systemImage: "arrow.counterclockwise") {
            model.applyControllerPreset(.twinCluster)
        }
        .frame(minHeight: SettingsSurfaceAccessibility.minimumInteractiveDimension)
    }

    private var mappingDeck: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                xCluster
                yCluster
                ControllerActionMappingView(model: model)
            }

            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    xCluster
                    yCluster
                }
                ControllerActionMappingView(model: model)
            }

            VStack(spacing: 14) {
                xCluster
                yCluster
                ControllerActionMappingView(model: model)
            }
        }
    }

    private var xCluster: some View {
        ControllerClusterMappingView(
            title: "X Cluster",
            subtitle: "Primary movement",
            controls: [.x1, .x2, .x3, .x4],
            model: model
        )
    }

    private var yCluster: some View {
        ControllerClusterMappingView(
            title: "Y Cluster",
            subtitle: "Rotation and second cluster",
            controls: [.y1, .y2, .y3, .y4],
            model: model
        )
    }
}

private struct ControllerClusterMappingView: View {
    let title: String
    let subtitle: String
    let controls: [WonderSwanControl]
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ControllerMappingKey(control: controls[0], model: model)
            HStack(spacing: 34) {
                ControllerMappingKey(control: controls[3], model: model)
                ControllerMappingKey(control: controls[1], model: model)
            }
            ControllerMappingKey(control: controls[2], model: model)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 268, maxHeight: 268)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ControllerActionMappingView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("Actions")
                    .font(.headline)
                Text("Buttons and console controls")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ControllerMappingKey(control: .a, model: model)
                ControllerMappingKey(control: .b, model: model)
            }
            HStack(spacing: 12) {
                ControllerMappingKey(control: .start, model: model)
                ControllerMappingKey(control: .volume, model: model)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 268, maxHeight: 268, alignment: .top)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ControllerMappingKey: View {
    let control: WonderSwanControl
    @Bindable var model: AppModel

    private var element: ControllerElement? {
        model.controllerProfile.element(for: control)
    }

    private var isLearning: Bool {
        model.controllerLearningControl == control
    }

    private var isActive: Bool {
        model.controllerInput.contains(control.engineInput)
    }

    var body: some View {
        Button {
            if isLearning {
                model.cancelLearningControllerBinding()
            } else {
                model.beginLearningControllerBinding(control)
            }
        } label: {
            VStack(spacing: 2) {
                Text(control.title)
                    .font(.caption2.monospaced().weight(.bold))
                Text(isLearning ? "PRESS…" : element?.shortTitle ?? "—")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isActive || isLearning ? Color.white : Color.primary)
            .frame(width: 74, height: 48)
            .background(
                isLearning ? Color.orange : isActive ? Color.accentColor : Color.primary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isLearning ? Color.orange : Color.accentColor.opacity(isActive ? 0.8 : 0.16), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map \(control.title)")
        .accessibilityValue(element?.title ?? "Unassigned")
        .accessibilityHint("Press a physical controller control, or use the binding menu")
        .overlay(alignment: .bottomTrailing) {
            Menu {
                ForEach(ControllerElement.allCases) { candidate in
                    Button {
                        model.setControllerBinding(control, to: candidate)
                    } label: {
                        if candidate == element {
                            Label(candidate.title, systemImage: "checkmark")
                        } else if let assigned = model.controllerProfile.control(for: candidate) {
                            Text("\(candidate.title) · currently \(assigned.title)")
                        } else {
                            Text(candidate.title)
                        }
                    }
                }
                Divider()
                Button("Clear Binding", systemImage: "xmark.circle", role: .destructive) {
                    model.setControllerBinding(control, to: nil)
                }
            } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .frame(
                        minWidth: SettingsSurfaceAccessibility.minimumInteractiveDimension,
                        minHeight: SettingsSurfaceAccessibility.minimumInteractiveDimension
                    )
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .offset(x: 7, y: 7)
            .help("Choose a binding for \(control.title)")
            .accessibilityLabel("Choose a binding for \(control.title)")
        }
        .animation(.easeOut(duration: 0.1), value: isActive)
        .animation(.easeOut(duration: 0.15), value: isLearning)
        .help("\(control.title): \(element?.title ?? "Unassigned")")
    }
}

private struct ControllerLiveInputView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            inputBadges(
                title: "Physical",
                values: ControllerElement.allCases
                    .filter(model.controllerPhysicalElements.contains)
                    .map(\.shortTitle)
            )
            inputBadges(
                title: "WonderSwan",
                values: WonderSwanControl.allCases
                    .filter { model.controllerInput.contains($0.engineInput) }
                    .map(\.title)
            )
        }
    }

    private func inputBadges(title: String, values: [String]) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            if values.isEmpty {
                Text("—")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.caption2.monospaced().weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.13), in: Capsule())
                }
            }
            Spacer()
        }
    }
}
