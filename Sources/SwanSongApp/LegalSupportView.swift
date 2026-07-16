import AppKit
import SwiftUI

enum LegalSupportSection: String, CaseIterable, Identifiable {
    case overview
    case updates
    case privacy
    case support
    case license
    case acknowledgements

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "About SwanSong"
        case .updates: "Updates"
        case .privacy: "Privacy"
        case .support: "Support"
        case .license: "License"
        case .acknowledgements: "Acknowledgements"
        }
    }

    var systemImage: String {
        switch self {
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
func presentLegalSupport(_ section: LegalSupportSection) {
    LegalSupportWindowController.shared.present(section)
}

struct LegalSupportCommands: Commands {
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
            Button("SwanSong Help…") { present(.support) }
                .keyboardShortcut("?", modifiers: .command)
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(updater.isConfigured && !updater.canCheckForUpdates)
            Button("Report a Problem…") { present(.support) }
        }
    }

    private func present(_ section: LegalSupportSection) {
        Task { @MainActor in
            presentLegalSupport(section)
        }
    }
}

@MainActor
private final class LegalSupportWindowController {
    static let shared = LegalSupportWindowController()

    private var window: NSWindow?

    func present(_ section: LegalSupportSection) {
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
        window.title = "Legal & Support"
        window.contentMinSize = CGSize(width: 720, height: 520)
        window.contentViewController = NSHostingController(
            rootView: LegalSupportView(updater: .shared)
        )
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SwanSongLegalSupportWindow")
        window.center()
        self.window = window
        return window
    }
}

struct LegalSupportView: View {
    @ObservedObject var updater: SwanSongUpdater
    @AppStorage("legalSupportSelectedSection") private var selectedSection =
        LegalSupportSection.overview.rawValue

    private let metadata = SwanSongMetadata.current

    init(updater: SwanSongUpdater = .shared) {
        self.updater = updater
    }

    private var selection: Binding<LegalSupportSection?> {
        Binding(
            get: { LegalSupportSection(rawValue: selectedSection) ?? .overview },
            set: { selectedSection = ($0 ?? .overview).rawValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(LegalSupportSection.allCases, selection: selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
        } detail: {
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
        .frame(minWidth: 720, minHeight: 520)
    }

    private var activeSection: LegalSupportSection {
        LegalSupportSection(rawValue: selectedSection) ?? .overview
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch activeSection {
        case .overview:
            overview
        case .updates:
            updates
        case .privacy:
            bundledMarkdown(named: "PRIVACY")
        case .support:
            support
        case .license:
            bundledPlainText(named: "LICENSE")
        case .acknowledgements:
            bundledMarkdown(named: "THIRD_PARTY_NOTICES")
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                SwanSongIcon(size: 88)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SwanSong")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("A private WonderSwan player and translation workbench for macOS.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            detailGrid

            Text(
                "SwanSong always starts games with its independently written Open IPL. No BIOS is needed or accepted. Add only game and homebrew images you own or are authorized to use."
            )
            .foregroundStyle(.secondary)

            Text(
                catalogOverviewText
            )
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Link(destination: SwanSongLinks.project) {
                    Label("Project Website", systemImage: "safari")
                }
                Link(destination: SwanSongLinks.releases) {
                    Label("Releases", systemImage: "arrow.down.circle")
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
                    ? "Checking contacts SwanSong’s GitHub-hosted signed update feed. Automatic checks and downloads remain off until you enable them in Settings."
                    : "The signed updater is unavailable in this build, so Check for Updates opens GitHub Releases in your default browser."
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

    var catalogOverviewText: String {
        switch HomebrewCatalogProductionTrust.publicationStatus {
        case .comingSoon:
            "The first-party Homebrew Catalog is coming soon and makes no network requests in this release. SwanSong does not upload your library, saves, states, screenshots, settings, or Translation Lab data."
        case .published:
            "The first-party Homebrew Catalog never loads at launch or in the background. After you choose Load Catalog once, opening Homebrew without a saved verified copy contacts GitHub; refreshing it or downloading a listed title does too. SwanSong does not upload your library, saves, states, screenshots, settings, or Translation Lab data."
        }
    }

    var catalogUpdatesDetail: String {
        switch HomebrewCatalogProductionTrust.publicationStatus {
        case .comingSoon:
            "SwanSong checks for app updates only when you ask or after you enable automatic checks. The Homebrew Catalog is coming soon and makes no network requests in this release."
        case .published:
            "SwanSong checks for app updates only when you ask or after you enable automatic checks. It does not refresh the Homebrew Catalog at launch or in the background. After catalog consent, opening Homebrew can request a missing verified copy; refresh remains an explicit action."
        }
    }

    var catalogNetworkDetail: String {
        switch HomebrewCatalogProductionTrust.publicationStatus {
        case .comingSoon:
            "Checking for app updates contacts only SwanSong’s GitHub-hosted feed and never sends a system profile. Opening Releases uses your browser. The unavailable Homebrew Catalog cannot contact GitHub in this release."
        case .published:
            "App updates and the Homebrew Catalog use separate GitHub requests. The updater never sends a system profile. The catalog contacts GitHub when Homebrew needs a missing verified copy, when you refresh it, or when you download a listed title. SwanSong does not attach library, save, or Translation Lab data."
        }
    }

    private var support: some View {
        VStack(alignment: .leading, spacing: 18) {
            bundledMarkdown(named: "SUPPORT")

            Divider()

            Text("Support tools")
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
            }

            Text(
                "Support information contains the app version, bundle ID, macOS version, and pinned engine revision. It does not include game names, private paths, ROM data, saves, or translation content."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
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
        if let text = BundledLegalDocument.text(named: name, extension: "md") {
            Text(BundledLegalDocument.markdown(text))
                .textSelection(.enabled)
                .lineSpacing(3)
        } else {
            unavailableDocument
        }
    }

    @ViewBuilder
    private func bundledPlainText(named name: String) -> some View {
        if let text = BundledLegalDocument.text(named: name) {
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

private enum BundledLegalDocument {
    static func text(named name: String, extension fileExtension: String? = nil) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func markdown(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        )) ?? AttributedString(source)
    }
}

private struct SwanSongMetadata {
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
    static let newIssue = URL(
        string: "https://github.com/RegionallyFamous/SwanSong-Desktop/issues/new/choose")!
}
