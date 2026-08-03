import AppKit
import SwanSongKit
import SwiftUI

enum LegalSupportSection: String, CaseIterable, Identifiable {
    case guide
    case whatsNew
    case overview
    case updates
    case privacy
    case support
    case license
    case acknowledgements

    var id: String { rawValue }

    var title: String {
        switch self {
        case .guide: "Start Here"
        case .whatsNew: "What’s New"
        case .overview: "About SwanSong"
        case .updates: "Updates"
        case .privacy: "Privacy & Trust"
        case .support: "Support"
        case .license: "License"
        case .acknowledgements: "Acknowledgements"
        }
    }

    var systemImage: String {
        switch self {
        case .guide: "sparkles"
        case .whatsNew: "gift"
        case .overview: "info.circle"
        case .updates: "arrow.down.circle"
        case .privacy: "hand.raised"
        case .support: "lifepreserver"
        case .license: "doc.text"
        case .acknowledgements: "person.2"
        }
    }
}

@MainActor
func presentLegalSupport(
    _ section: LegalSupportSection,
    model: AppModel? = nil
) {
    LegalSupportWindowController.shared.present(section, model: model)
}

enum SwanSongGuideLaunchPolicy {
    static let presentedDefaultsKey = "SwanSong.guide.hasPresented.v1"
    static let releaseStoryDefaultsKey = "SwanSong.releaseStory.lastPresented.v1"
    static let releaseStoryVersion = SwanSongReleaseStory.series

    static func shouldPresent(
        guideHasPresented: Bool,
        hasGames: Bool,
        isSafeMode: Bool,
        suppressesWelcome: Bool,
        hasInitialOpenRequest: Bool
    ) -> Bool {
        !guideHasPresented
            && !hasGames
            && !isSafeMode
            && !suppressesWelcome
            && !hasInitialOpenRequest
    }

    static func shouldPresent(
        userDefaults: UserDefaults = .standard,
        hasGames: Bool,
        isSafeMode: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> Bool {
        shouldPresent(
            guideHasPresented: userDefaults.bool(forKey: presentedDefaultsKey),
            hasGames: hasGames,
            isSafeMode: isSafeMode,
            suppressesWelcome: environment["SWAN_SONG_HEADLESS"] == "1"
                || environment["SWAN_SONG_SUPPRESS_WELCOME"] == "1",
            hasInitialOpenRequest: environment["SWAN_SONG_INITIAL_ROM"]?.isEmpty == false
                || arguments.dropFirst().contains(where: isSupportedOpenRequest)
        )
    }

    static func markPresented(userDefaults: UserDefaults = .standard) {
        markPresented(.guide, userDefaults: userDefaults)
    }

    static func launchSection(
        guideHasPresented: Bool,
        lastPresentedReleaseStory: String?,
        installedVersion: String,
        hasGames: Bool,
        isSafeMode: Bool,
        suppressesWelcome: Bool,
        hasInitialOpenRequest: Bool
    ) -> LegalSupportSection? {
        guard !isSafeMode,
              !suppressesWelcome,
              !hasInitialOpenRequest else { return nil }

        if !guideHasPresented, !hasGames {
            return .guide
        }
        if hasGames,
           (installedVersion == releaseStoryVersion
                || installedVersion.hasPrefix("\(releaseStoryVersion).")),
           lastPresentedReleaseStory != releaseStoryVersion {
            return .whatsNew
        }
        return nil
    }

    static func launchSection(
        userDefaults: UserDefaults = .standard,
        installedVersion: String,
        hasGames: Bool,
        isSafeMode: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> LegalSupportSection? {
        launchSection(
            guideHasPresented: userDefaults.bool(forKey: presentedDefaultsKey),
            lastPresentedReleaseStory: userDefaults.string(
                forKey: releaseStoryDefaultsKey
            ),
            installedVersion: installedVersion,
            hasGames: hasGames,
            isSafeMode: isSafeMode,
            suppressesWelcome: environment["SWAN_SONG_HEADLESS"] == "1"
                || environment["SWAN_SONG_SUPPRESS_WELCOME"] == "1",
            hasInitialOpenRequest: environment["SWAN_SONG_INITIAL_ROM"]?.isEmpty == false
                || arguments.dropFirst().contains(where: isSupportedOpenRequest)
        )
    }

    static func markPresented(
        _ section: LegalSupportSection,
        userDefaults: UserDefaults = .standard
    ) {
        if section == .guide {
            userDefaults.set(true, forKey: presentedDefaultsKey)
        }
        if section == .guide || section == .whatsNew {
            userDefaults.set(releaseStoryVersion, forKey: releaseStoryDefaultsKey)
        }
    }

    private static func isSupportedOpenRequest(_ argument: String) -> Bool {
        let supportedExtensions = Set(["ws", "wsc", "pc2", "pcv2", "zip"])
        return supportedExtensions.contains(
            URL(fileURLWithPath: argument).pathExtension.lowercased()
        )
    }
}

struct LegalSupportCommands: Commands {
    let model: AppModel
    @ObservedObject var updater: SwanSongUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Divider()
            Button("Privacy…") { present(.privacy) }
            Button("Support…") { present(.support) }
            Button("License…") { present(.license) }
            Button("Acknowledgements…") { present(.acknowledgements) }
        }

        CommandGroup(replacing: .help) {
            Button("SwanSong Guide…") { present(.guide) }
                .keyboardShortcut("?", modifiers: .command)
            Button("What’s New in SwanSong \(SwanSongReleaseStory.series)…") {
                present(.whatsNew)
            }

            Divider()

            Button("SwanSong Support…") { present(.support) }
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(updater.isConfigured && !updater.canCheckForUpdates)
            Button("Report a Problem…") { present(.support) }
        }
    }

    private func present(_ section: LegalSupportSection) {
        Task { @MainActor in
            presentLegalSupport(section, model: model)
        }
    }
}

@MainActor
private final class LegalSupportWindowController {
    static let shared = LegalSupportWindowController()

    private var window: NSWindow?
    private weak var model: AppModel?

    func present(_ section: LegalSupportSection, model: AppModel? = nil) {
        if let model {
            self.model = model
        }
        UserDefaults.standard.set(
            section.rawValue,
            forKey: "legalSupportSelectedSection"
        )

        let window = window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 820, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SwanSong Guide & Support"
        window.contentMinSize = CGSize(width: 720, height: 520)
        window.contentViewController = NSHostingController(
            rootView: LegalSupportView(
                updater: .shared,
                onOpenGame: { [weak self] in
                    self?.openGame()
                },
                onNavigate: { [weak self] section in
                    self?.navigate(to: section)
                }
            )
        )
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SwanSongLegalSupportWindow")
        window.center()
        self.window = window
        return window
    }

    private func openGame() {
        window?.orderOut(nil)
        model?.chooseGame()
    }

    private func navigate(to section: AppModel.Section) {
        window?.orderOut(nil)
        model?.section = section
        NSApp.windows.first(where: { $0.title == "SwanSong" })?
            .makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct LegalSupportView: View {
    @ObservedObject var updater: SwanSongUpdater
    @AppStorage("legalSupportSelectedSection") private var selectedSection =
        LegalSupportSection.overview.rawValue
    private let fixedSection: LegalSupportSection?
    private let bundledDocumentOverrides: [String: String]
    private let usesDeterministicSidebarForOffscreenSnapshots: Bool
    private let metadata: SwanSongMetadata
    private let onOpenGame: (() -> Void)?
    private let onNavigate: ((AppModel.Section) -> Void)?
    @State private var localControlEnabled = UserDefaults.standard.bool(
        forKey: SwanSongLocalMCPAccess.enabledDefaultsKey
    )
    @State private var supportBundleIsExporting = false
    @State private var supportBundleMessage: String?

    init(
        updater: SwanSongUpdater = .shared,
        fixedSection: LegalSupportSection? = nil,
        bundledDocumentOverrides: [String: String] = [:],
        usesDeterministicSidebarForOffscreenSnapshots: Bool = false,
        metadata: SwanSongMetadata = .current,
        onOpenGame: (() -> Void)? = nil,
        onNavigate: ((AppModel.Section) -> Void)? = nil
    ) {
        self.updater = updater
        self.fixedSection = fixedSection
        self.bundledDocumentOverrides = bundledDocumentOverrides
        self.usesDeterministicSidebarForOffscreenSnapshots =
            usesDeterministicSidebarForOffscreenSnapshots
        self.metadata = metadata
        self.onOpenGame = onOpenGame
        self.onNavigate = onNavigate
    }

    private var selection: Binding<LegalSupportSection?> {
        Binding(
            get: {
                fixedSection
                    ?? LegalSupportSection(rawValue: selectedSection)
                    ?? .overview
            },
            set: { selection in
                guard fixedSection == nil else { return }
                selectedSection = (selection ?? .overview).rawValue
            }
        )
    }

    var body: some View {
        Group {
            if usesDeterministicSidebarForOffscreenSnapshots {
                HStack(spacing: 0) {
                    snapshotSidebar
                        .frame(width: 210)
                    Divider()
                    detailContent
                }
            } else {
                NavigationSplitView {
                    List(LegalSupportSection.allCases, selection: selection) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
                } detail: {
                    detailContent
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionContent
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(28)
        }
        .navigationTitle(activeSection.title)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var snapshotSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HELP & INFO")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 4)

            ForEach(LegalSupportSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(
                        section == activeSection ? Color.accentColor : Color.primary
                    )
                    .background(
                        section == activeSection
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var activeSection: LegalSupportSection {
        fixedSection
            ?? LegalSupportSection(rawValue: selectedSection)
            ?? .overview
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch activeSection {
        case .guide:
            guide
        case .whatsNew:
            whatsNew
        case .overview:
            overview
        case .updates:
            updates
        case .privacy:
            privacyAndTrust
        case .support:
            support
        case .license:
            bundledPlainText(named: "LICENSE")
        case .acknowledgements:
            bundledMarkdown(named: "THIRD_PARTY_NOTICES")
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 18) {
                SwanSongIcon(size: 82)
                VStack(alignment: .leading, spacing: 5) {
                    Text(SwanSongProductCopy.tagline)
                        .font(.largeTitle.bold())
                    Text(SwanSongProductCopy.playerSummary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                trustPill("No account", symbol: "person.crop.circle.badge.xmark")
                trustPill("No ads", symbol: "rectangle.slash")
                trustPill("No telemetry", symbol: "hand.raised")
            }

            GroupBox("Your First Three Steps") {
                VStack(alignment: .leading, spacing: 0) {
                    guideStep(
                        1,
                        title: "Add a game you own",
                        detail: "Open a .ws, .wsc, .pc2, .pcv2, or one-game ZIP. SwanSong validates it and keeps a private library copy."
                    )
                    Divider().padding(.leading, 46)
                    guideStep(
                        2,
                        title: "Press Play",
                        detail: "SwanSong fits horizontal and vertical games automatically. Arrows and WASD control the two direction pads; Z is B, X is A, and Return is Start."
                    )
                    Divider().padding(.leading, 46)
                    guideStep(
                        3,
                        title: "Save or rewind whenever you like",
                        detail: "Time Ribbon rewinds the last 30 seconds. The visual Save-State Timeline keeps the moments you choose without turning them into file-management chores."
                    )
                }
                .padding(6)
            }

            if let onOpenGame {
                Button {
                    onOpenGame()
                } label: {
                    Label("Open Your First Game…", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Label(
                "Open this guide anytime from the Help menu.",
                systemImage: "questionmark.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("swan-song-start-here")
    }

    private func guideStep(
        _ number: Int,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(SwanTheme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
    }

    private func trustPill(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var whatsNew: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SwanSong \(SwanSongReleaseStory.series)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(SwanTheme.accent)
                Text("Bring the Translation Home")
                    .font(.largeTitle.bold())
                Text("A trusted translation release can now have its own place in your library—without changing the original.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            releaseSpotlight(
                title: "Verified from end to end",
                detail: "Choose a release package and the exact original it asks for. SwanSong verifies the release, patch, source revision, finished game, cartridge checksum, and save contract before it adds anything.",
                symbol: "character.book.closed.fill",
                tint: SwanTheme.violet
            )
            releaseSpotlight(
                title: "The original stays original",
                detail: "Patching happens in memory, so the original game never changes. The translated version has separate saves and states of its own.",
                symbol: "checkmark.shield.fill",
                tint: .green
            )
            releaseSpotlight(
                title: "A real home in your library",
                detail: "The translated game gets its own artwork, favorite, and play history. If its library copy is damaged, SwanSong can rebuild it without losing your place.",
                symbol: "books.vertical.fill",
                tint: SwanTheme.cyan
            )

            GroupBox("Also polished in 0.9") {
                VStack(alignment: .leading, spacing: 9) {
                    Label(
                        "Seven approved Homebrew title screens have fresh native captures.",
                        systemImage: "photo.on.rectangle.angled"
                    )
                    Label(
                        "Translation Shelf is source-free, network-silent, and fails closed on mismatches.",
                        systemImage: "network.slash"
                    )
                    Label(
                        "The everyday library stays focused on choosing a game and playing it.",
                        systemImage: "play.rectangle"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            HStack(spacing: 12) {
                if let onNavigate {
                    Button {
                        onNavigate(.translationPatches)
                    } label: {
                        Label("Open Translation Shelf", systemImage: "character.book.closed.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Link(destination: SwanSongLinks.currentReleaseNotes) {
                    Label("Read Complete Release Notes", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }
        }
        .accessibilityIdentifier("swan-song-whats-new")
    }

    private func releaseSpotlight(
        title: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                SwanSongIcon(size: 88)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SwanSong")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(SwanSongProductCopy.playerSummary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            detailGrid

            Text(
                "No BIOS hunt required: SwanSong starts games with its independently written Open IPL. Add only games and homebrew you own or are allowed to use."
            )
            .foregroundStyle(.secondary)

            Text(
                catalogOverviewText
            )
            .foregroundStyle(.secondary)

            GroupBox("Why SwanSong Exists") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "The WonderSwan was opinionated: two direction clusters, games that turn sideways, wonderful homebrew, and a small but determined translation scene. SwanSong is built to preserve that character instead of sanding it into a generic emulator."
                    )
                    Text(
                        "Its promise is simple: everyday play should feel effortless, deeper tools should be there when invited, and confidence should come from inspectable evidence rather than a cheerful badge."
                    )
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            HStack(spacing: 12) {
                Link(destination: SwanSongLinks.project) {
                    Label("Visit SwanSong", systemImage: "safari")
                }
                Link(destination: SwanSongLinks.releases) {
                    Label("See What’s New", systemImage: "arrow.down.circle")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var detailGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
            detailRow("Version", metadata.versionAndBuild)
            detailRow("Publisher", "Regionally Famous")
            detailRow("Bundle ID", metadata.bundleIdentifier)
            detailRow("Requires", "macOS 14 or later")
            detailRow("Engine", metadata.engineDescription)
        }
        .textSelection(.enabled)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    private var updates: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(
                "Updates",
                detail: catalogUpdatesDetail
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Installed version", systemImage: "checkmark.seal")
                        .font(.headline)
                    Text(metadata.versionAndBuild)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Button {
                updater.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(updater.isConfigured && !updater.canCheckForUpdates)

            Button {
                updater.openReleases()
            } label: {
                Label("Open SwanSong Releases", systemImage: "safari")
            }
            .buttonStyle(.bordered)

            Text(
                updater.isConfigured
                    ? "SwanSong checks its signed update feed on GitHub. Automatic checks and downloads stay off until you turn them on in Settings."
                    : "Updates are not built into this copy, so Check for Updates opens the official GitHub Releases page in your browser."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Text(
                catalogNetworkDetail
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var privacyAndTrust: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading(
                "Private by Design",
                detail: "Your games and projects stay on your Mac. SwanSong has no accounts, analytics, advertising, telemetry, or crash-reporting service."
            )

            trustCard(
                title: "No Tracking or Data Collection",
                symbol: "hand.raised.fill",
                tint: .green,
                detail: "The bundled Apple privacy manifest declares no tracking and no collected data."
            )
            trustCard(
                title: "Signed, Notarized Updates",
                symbol: updater.isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                tint: updater.isConfigured ? .green : .orange,
                detail: updater.isConfigured
                    ? "Every update must match SwanSong’s embedded EdDSA key before Sparkle can install it. No system profile is sent."
                    : "This development copy does not have the production update trust configuration."
            )
            trustCard(
                title: "Homebrew Trust",
                symbol: "shippingbox.fill",
                tint: .blue,
                detail: HomebrewCatalogProductionTrust.publicationStatus == .published
                    ? "Catalog metadata and downloads are accepted only after their pinned signatures and hashes verify."
                    : "The first-party catalog is not published, so this build cannot make catalog requests."
            )
            trustCard(
                title: "Local Automation",
                symbol: localControlEnabled ? "lock.open.fill" : "lock.fill",
                tint: localControlEnabled ? .orange : .green,
                detail: localControlEnabled
                    ? "Enabled for SwanSong’s signed local helper. Requests use a private, same-user socket and never expose game bytes, saves, screenshots, memory, or project files."
                    : "Off. Local tools cannot control SwanSong."
            )

            if localControlEnabled {
                Button("Turn Off Local Automation") {
                    UserDefaults.standard.set(
                        false,
                        forKey: SwanSongLocalMCPAccess.enabledDefaultsKey
                    )
                    localControlEnabled = false
                }
                .buttonStyle(.bordered)
            }

            GroupBox("When SwanSong Goes Online") {
                VStack(alignment: .leading, spacing: 10) {
                    networkRow(
                        "App updates",
                        "raw.githubusercontent.com — only when you ask or enable automatic checks"
                    )
                    networkRow(
                        "Releases and support",
                        "github.com — opens in your browser only after you choose a link"
                    )
                    networkRow(
                        "Homebrew catalog",
                        "GitHub — only after you choose Browse Games, Refresh, or a download"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox("Your Data") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Games managed by SwanSong, saves, states, artwork, preferences, and cached catalog data live in SwanSong’s private Application Support folder. Linked Translation Lab projects stay where you put them.")
                        .foregroundStyle(.secondary)
                    Button("Show SwanSong Data in Finder") {
                        let url = SwanSongDataRootPolicy.defaultResolution().rootURL
                        try? FileManager.default.createDirectory(
                            at: url,
                            withIntermediateDirectories: true
                        )
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Divider()
            bundledMarkdown(named: "PRIVACY")
        }
    }

    private func trustCard(
        title: String,
        symbol: String,
        tint: Color,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            tint.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func networkRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.medium)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }

    var catalogOverviewText: String {
        switch HomebrewCatalogProductionTrust.publicationStatus {
        case .comingSoon:
            "The first-party Homebrew Catalog is coming soon and makes no network requests in this release. SwanSong does not upload your library, saves, states, screenshots, settings, or Translation Lab data."
        case .published:
            "The signed Homebrew Catalog never loads at launch, when you open Homebrew, or in the background. Choosing Browse Games, Refresh, or a listed download contacts GitHub. SwanSong does not upload your library, saves, states, screenshots, settings, or Translation Lab data."
        }
    }

    var catalogUpdatesDetail: String {
        switch HomebrewCatalogProductionTrust.publicationStatus {
        case .comingSoon:
            "SwanSong checks for app updates only when you ask or after you enable automatic checks. The Homebrew Catalog is coming soon and makes no network requests in this release."
        case .published:
            "SwanSong checks for app updates only when you ask or after you enable automatic checks. It does not refresh Homebrew at launch, on navigation, or in the background. Browse Games and Refresh are choices you make."
        }
    }

    var catalogNetworkDetail: String {
        switch HomebrewCatalogProductionTrust.publicationStatus {
        case .comingSoon:
            "Checking for app updates contacts only SwanSong’s GitHub-hosted feed and never sends a system profile. Opening Releases uses your browser. The unavailable Homebrew Catalog cannot contact GitHub in this release."
        case .published:
            "App updates and Homebrew use separate GitHub requests. The updater never sends a system profile. Homebrew contacts GitHub only when you choose Browse Games, Refresh, or a listed download. SwanSong does not attach library, save, or Translation Lab data."
        }
    }

    private var support: some View {
        VStack(alignment: .leading, spacing: 18) {
            bundledMarkdown(named: "SUPPORT")

            Divider()

            Text("Need a Hand?")
                .font(.title2.weight(.semibold))

            HStack(spacing: 12) {
                Link(destination: SwanSongLinks.newIssue) {
                    Label("Report a Problem", systemImage: "exclamationmark.bubble")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    metadata.copySupportInformation()
                } label: {
                    Label("Copy Support Information", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    createSupportBundle()
                } label: {
                    Label(
                        supportBundleIsExporting ? "Creating…" : "Create Support Bundle…",
                        systemImage: "shippingbox.and.arrow.backward"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(supportBundleIsExporting)
            }

            Text(
                "Support information includes the app, macOS, and game-engine versions. It never includes game names, private paths, game data, saves, or translation content."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            if let supportBundleMessage {
                Label(supportBundleMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Restart SwanSong in Safe Mode…") {
                SwanSongLaunchRecovery.restartInSafeMode()
            }
            .buttonStyle(.link)
        }
    }

    private func createSupportBundle() {
        supportBundleIsExporting = true
        supportBundleMessage = nil
        let snapshot = SwanSongSupportBundleSnapshot.current(
            metadata: metadata,
            updater: updater,
            safeMode: UserDefaults.standard.bool(
                forKey: SwanSongLaunchRecovery.currentSafeModeDefaultsKey
            )
        )
        Task { @MainActor in
            defer { supportBundleIsExporting = false }
            do {
                guard let url = try await SwanSongSupportBundleExporter
                    .chooseDestinationAndExport(snapshot: snapshot) else { return }
                supportBundleMessage = "Support bundle created."
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                supportBundleMessage = "The support bundle could not be created: \(error.localizedDescription)"
            }
        }
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.bold())
            Text(detail)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func bundledMarkdown(named name: String) -> some View {
        if let text = bundledDocumentOverrides[name]
            ?? BundledLegalDocument.text(named: name, extension: "md") {
            BundledMarkdownDocument(source: text)
        } else {
            unavailableDocument
        }
    }

    @ViewBuilder
    private func bundledPlainText(named name: String) -> some View {
        if let text = bundledDocumentOverrides[name]
            ?? BundledLegalDocument.text(named: name) {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineSpacing(2)
        } else {
            unavailableDocument
        }
    }

    private var unavailableDocument: some View {
        ContentUnavailableView(
            "Document Unavailable",
            systemImage: "doc.badge.ellipsis",
            description: Text("This document is missing from the application bundle.")
        )
    }
}

struct BundledMarkdownDocument: View {
    let blocks: [BundledLegalDocument.MarkdownBlock]

    init(source: String) {
        blocks = BundledLegalDocument.markdownBlocks(source)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: BundledLegalDocument.MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, source):
            Text(BundledLegalDocument.inlineMarkdown(source))
                .font(headingFont(level))
                .padding(.top, level == 1 ? 0 : 8)
                .fixedSize(horizontal: false, vertical: true)
        case let .paragraph(source):
            Text(BundledLegalDocument.inlineMarkdown(source))
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case let .unorderedList(items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text(BundledLegalDocument.inlineMarkdown(item))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 6)
        case let .orderedList(items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)
                        Text(BundledLegalDocument.inlineMarkdown(item))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .largeTitle.bold()
        case 2: .title2.weight(.semibold)
        default: .title3.weight(.semibold)
        }
    }
}

enum BundledLegalDocument {
    enum MarkdownBlock: Equatable {
        case heading(level: Int, source: String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList([String])
        case divider
    }

    static func text(named name: String, extension fileExtension: String? = nil) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func inlineMarkdown(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(source)
    }

    static func markdownBlocks(_ source: String) -> [MarkdownBlock] {
        let lines = removingHTMLComments(from: source)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var listIsOrdered: Bool?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll(keepingCapacity: true)
        }

        func flushList() {
            guard let ordered = listIsOrdered, !listItems.isEmpty else { return }
            blocks.append(ordered ? .orderedList(listItems) : .unorderedList(listItems))
            listItems.removeAll(keepingCapacity: true)
            listIsOrdered = nil
        }

        func startListItem(_ item: String, ordered: Bool) {
            flushParagraph()
            if let listIsOrdered, listIsOrdered != ordered {
                flushList()
            }
            listIsOrdered = ordered
            listItems.append(item)
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if let heading = heading(in: trimmed) {
                flushParagraph()
                flushList()
                blocks.append(.heading(level: heading.level, source: heading.source))
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                flushList()
                blocks.append(.divider)
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                startListItem(String(trimmed.dropFirst(2)), ordered: false)
                continue
            }

            if let item = orderedListItem(in: trimmed) {
                startListItem(item, ordered: true)
                continue
            }

            if listIsOrdered != nil, rawLine.first?.isWhitespace == true,
                !listItems.isEmpty
            {
                listItems[listItems.count - 1] += " " + trimmed
                continue
            }

            flushList()
            paragraph.append(trimmed)
        }

        flushParagraph()
        flushList()
        return blocks
    }

    private static func heading(in line: String) -> (level: Int, source: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1 ... 6).contains(level) else { return nil }
        let markerEnd = line.index(line.startIndex, offsetBy: level)
        guard markerEnd < line.endIndex, line[markerEnd] == " " else { return nil }
        return (
            min(level, 3),
            String(line[line.index(after: markerEnd)...])
        )
    }

    private static func orderedListItem(in line: String) -> String? {
        guard let period = line.firstIndex(of: "."), period > line.startIndex else {
            return nil
        }
        let number = line[..<period]
        guard number.allSatisfy(\.isNumber) else { return nil }
        let contentStart = line.index(after: period)
        guard contentStart < line.endIndex, line[contentStart] == " " else { return nil }
        return String(line[line.index(after: contentStart)...])
    }

    private static func removingHTMLComments(from source: String) -> String {
        var result = ""
        var remainder = source[...]

        while let opening = remainder.range(of: "<!--") {
            result += remainder[..<opening.lowerBound]
            guard let closing = remainder[opening.upperBound...].range(of: "-->") else {
                return result
            }
            remainder = remainder[closing.upperBound...]
        }
        result += remainder
        return result
    }
}

struct SwanSongMetadata {
    let version: String
    let build: String
    let bundleIdentifier: String
    let aresRevision: String?

    static var current: SwanSongMetadata {
        let info = Bundle.main.infoDictionary ?? [:]
        return SwanSongMetadata(
            version: info["CFBundleShortVersionString"] as? String ?? "Development",
            build: info["CFBundleVersion"] as? String ?? "Local",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.regionallyfamous.swansong",
            aresRevision: bundledAresRevision()
        )
    }

    var versionAndBuild: String { "\(version) (\(build))" }

    var engineDescription: String {
        guard let aresRevision else { return "ares · pinned revision" }
        return "ares · \(aresRevision.prefix(12))"
    }

    var supportInformation: String {
        [
            "SwanSong \(versionAndBuild)",
            "Bundle ID: \(bundleIdentifier)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Engine: \(engineDescription)",
        ].joined(separator: "\n")
    }

    func copySupportInformation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(supportInformation, forType: .string)
    }

    private static func bundledAresRevision() -> String? {
        guard let url = Bundle.main.url(forResource: "ares.lock", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object["commit"] as? String
    }
}

enum SwanSongLinks {
    static let project = URL(string: "https://github.com/RegionallyFamous/SwanSong-Desktop")!
    static let releases = URL(
        string: "https://github.com/RegionallyFamous/SwanSong-Desktop/releases")!
    static let currentReleaseNotes = URL(
        string: "https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/docs/releases/\(SwanSongReleaseStory.fullVersion).md")!
    static let newIssue = URL(
        string: "https://github.com/RegionallyFamous/SwanSong-Desktop/issues/new/choose")!
}

enum SwanSongReleaseStory {
    static let series = "0.9"
    static let fullVersion = "0.9.4"
}
