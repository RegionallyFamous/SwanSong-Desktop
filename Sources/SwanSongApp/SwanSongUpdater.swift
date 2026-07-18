import AppKit
import Foundation
import Sparkle
import SwiftUI

struct AppUpdateConfiguration: Equatable {
    static let feedURLKey = "SUFeedURL"
    static let publicKeyKey = "SUPublicEDKey"
    static let requiredBooleanPolicies: [String: Bool] = [
        "SUAutomaticallyUpdate": false,
        "SUEnableAutomaticChecks": false,
        "SUEnableSystemProfiling": false,
        "SUSendProfileInfo": false,
        "SURequireSignedFeed": true,
        "SUVerifyUpdateBeforeExtraction": true,
    ]
    static let expectedFeedURL = URL(
        string: "https://raw.githubusercontent.com/RegionallyFamous/SwanSong-Desktop/main/updates/appcast.xml"
    )!

    let feedURL: URL
    let publicKey: String

    init(infoDictionary: [String: Any]) throws {
        guard
            let feedValue = infoDictionary[Self.feedURLKey] as? String,
            let feedURL = URL(string: feedValue)
        else {
            throw AppUpdateConfigurationError.missingFeedURL
        }
        guard feedURL == Self.expectedFeedURL else {
            throw AppUpdateConfigurationError.untrustedFeedURL
        }

        guard
            let publicKey = infoDictionary[Self.publicKeyKey] as? String,
            !publicKey.isEmpty
        else {
            throw AppUpdateConfigurationError.missingPublicKey
        }
        guard
            let publicKeyData = Data(base64Encoded: publicKey),
            publicKeyData.count == 32
        else {
            throw AppUpdateConfigurationError.invalidPublicKey
        }
        for (key, requiredValue) in Self.requiredBooleanPolicies {
            guard infoDictionary[key] as? Bool == requiredValue else {
                throw AppUpdateConfigurationError.unsafeUpdaterPolicy
            }
        }

        self.feedURL = feedURL
        self.publicKey = publicKey
    }
}

enum AppUpdateConfigurationError: LocalizedError, Equatable {
    case missingFeedURL
    case untrustedFeedURL
    case missingPublicKey
    case invalidPublicKey
    case unsafeUpdaterPolicy

    var errorDescription: String? {
        switch self {
        case .missingFeedURL:
            "The signed update feed is not configured in this build."
        case .untrustedFeedURL:
            "This build does not point to SwanSong’s GitHub-hosted update feed."
        case .missingPublicKey:
            "The update-signing public key is not configured in this build."
        case .invalidPublicKey:
            "The update-signing public key in this build is invalid."
        case .unsafeUpdaterPolicy:
            "This build does not enforce SwanSong’s update privacy and signature policy."
        }
    }
}

enum AppUpdateChannelPolicy {
    static let betaChannel = "beta"

    static func allowedChannels(includeBeta: Bool) -> Set<String> {
        includeBeta ? [betaChannel] : []
    }
}

enum AppUpdateNetworkPolicy {
    static let allowedSystemProfileKeys: [String] = []

    static func shouldResetUpdateCycle(automaticallyChecksForUpdates: Bool) -> Bool {
        automaticallyChecksForUpdates
    }
}

private final class SwanSongUpdateChannelDelegate: NSObject, SPUUpdaterDelegate {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        AppUpdateChannelPolicy.allowedChannels(
            includeBeta: userDefaults.bool(forKey: SwanSongUpdater.includeBetaUpdatesKey)
        )
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        AppUpdateNetworkPolicy.allowedSystemProfileKeys
    }
}

@MainActor
final class SwanSongUpdater: NSObject, ObservableObject {
    static let includeBetaUpdatesKey = "SwanSongIncludeBetaUpdates"
    static let sendProfileInfoKey = "SUSendProfileInfo"
    static let shared = SwanSongUpdater()

    private let userDefaults: UserDefaults
    private let channelDelegate: SwanSongUpdateChannelDelegate
    private var updaterController: SPUStandardUpdaterController?
    private var updaterObservations: [NSKeyValueObservation] = []

    let configurationIssue: String?
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var allowsAutomaticDownloads = false

    override convenience init() {
        self.init(bundle: .main, userDefaults: .standard)
    }

    init(bundle: Bundle, userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        channelDelegate = SwanSongUpdateChannelDelegate(userDefaults: userDefaults)

        do {
            _ = try AppUpdateConfiguration(infoDictionary: bundle.infoDictionary ?? [:])
            configurationIssue = nil
        } catch {
            configurationIssue = error.localizedDescription
        }

        super.init()

        guard configurationIssue == nil else { return }
        // Sparkle's SUEnableSystemProfiling key controls whether its permission
        // prompt offers profiling. SUSendProfileInfo is the independent,
        // persisted value that actually controls whether profile fields are
        // attached to feed requests. Clear it before starting the updater so a
        // stale preference cannot escape SwanSong's no-profile policy.
        userDefaults.set(false, forKey: Self.sendProfileInfoKey)
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: channelDelegate,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController
        updaterController.updater.sendsSystemProfile = false
        observe(updaterController.updater)
    }

    var isConfigured: Bool { updaterController != nil }

    var includesBetaUpdates: Bool {
        userDefaults.bool(forKey: Self.includeBetaUpdatesKey)
    }

    func checkForUpdates() {
        guard let updaterController else {
            openReleases()
            return
        }
        updaterController.updater.sendsSystemProfile = false
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        if !enabled {
            updater.automaticallyDownloadsUpdates = false
        }
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticDownloads = updater.allowsAutomaticUpdates
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyDownloadsUpdates = enabled && updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    func setIncludesBetaUpdates(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: Self.includeBetaUpdatesKey)
        if let updater = updaterController?.updater,
           AppUpdateNetworkPolicy.shouldResetUpdateCycle(
               automaticallyChecksForUpdates: updater.automaticallyChecksForUpdates
           )
        {
            updater.resetUpdateCycleAfterShortDelay()
        }
        objectWillChange.send()
    }

    func openReleases() {
        NSWorkspace.shared.open(SwanSongLinks.releases)
    }

    private func observe(_ updater: SPUUpdater) {
        updaterObservations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
                [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor [weak self] in
                    self?.canCheckForUpdates = value
                }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) {
                [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor [weak self] in
                    self?.automaticallyChecksForUpdates = value
                }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) {
                [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor [weak self] in
                    self?.automaticallyDownloadsUpdates = value
                }
            },
            updater.observe(\.allowsAutomaticUpdates, options: [.initial, .new]) {
                [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor [weak self] in
                    self?.allowsAutomaticDownloads = value
                }
            },
            updater.observe(\.sendsSystemProfile, options: [.initial, .new]) {
                [weak updater] _, change in
                guard change.newValue == true else { return }
                Task { @MainActor in
                    updater?.sendsSystemProfile = false
                }
            },
        ]
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var updater: SwanSongUpdater

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                updateHeader

                if updater.isConfigured {
                    settingsCard(
                        title: "Keep SwanSong Updated",
                        symbol: "arrow.triangle.2.circlepath"
                    ) {
                        Toggle(
                            "Automatically check for updates",
                            isOn: Binding(
                                get: { updater.automaticallyChecksForUpdates },
                                set: { updater.setAutomaticallyChecksForUpdates($0) }
                            )
                        )

                        Toggle(
                            "Automatically download and install updates",
                            isOn: Binding(
                                get: { updater.automaticallyDownloadsUpdates },
                                set: { updater.setAutomaticallyDownloadsUpdates($0) }
                            )
                        )
                        .disabled(
                            !updater.automaticallyChecksForUpdates
                                || !updater.allowsAutomaticDownloads
                        )

                        Text(
                            "You’re in control: both options stay off until you turn them on. SwanSong never sends a system profile when it checks."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    settingsCard(
                        title: "Early Access",
                        symbol: "point.3.connected.trianglepath.dotted"
                    ) {
                        Toggle(
                            "Try beta versions",
                            isOn: Binding(
                                get: { updater.includesBetaUpdates },
                                set: { updater.setIncludesBetaUpdates($0) }
                            )
                        )
                        Text(
                            "Stable releases are always included. Betas let you try new ideas sooner, but they may be less reliable."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        SwanIconTile(
                            symbol: "exclamationmark.triangle.fill",
                            tint: .orange,
                            size: 48
                        )
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Updates Aren’t Available in This Build")
                                .font(.headline)
                            Text(
                                updater.configurationIssue
                                    ?? "The signed updater is unavailable in this build."
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(18)
                    .swanSurface(.standard, tint: .orange, cornerRadius: 16)
                }

                settingsCard(title: "Check Now", symbol: "arrow.down.circle.fill") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            updateButtons
                            Spacer(minLength: 0)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            updateButtons
                        }
                    }

                    Divider()

                    Label(
                        "Checking uses SwanSong’s GitHub-hosted feed. Opening Releases uses your default browser.",
                        systemImage: "network"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.title3)
                        .foregroundStyle(SwanTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Private by design")
                            .font(.callout.weight(.semibold))
                        Text(
                            "Update checks never include a system profile. Automatic checks and downloads stay off until you turn them on."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .swanSurface(.recessed, tint: SwanTheme.accent, cornerRadius: 15)
            }
            .padding(24)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(SwanTheme.libraryBackground.ignoresSafeArea())
    }

    private var updateHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            SwanIconTile(
                symbol: "arrow.down.circle.fill",
                tint: SwanTheme.accent,
                size: 56
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Stay Up to Date")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "Every update is signed and checked before SwanSong installs it. Releases come from the official GitHub project."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .swanSurface(.elevated, tint: SwanTheme.accent, cornerRadius: 18)
    }

    @ViewBuilder
    private var updateButtons: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(updater.isConfigured && !updater.canCheckForUpdates)
        .buttonStyle(.borderedProminent)

        Button("Open SwanSong Releases") {
            updater.openReleases()
        }
        .buttonStyle(.bordered)
    }

    private func settingsCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Divider()
            content()
        }
        .padding(18)
        .swanSurface(.standard, tint: SwanTheme.accent, cornerRadius: 16)
    }
}
