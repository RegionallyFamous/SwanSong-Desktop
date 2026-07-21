import AppKit
import CryptoKit
import Foundation
import SwanSongKit

struct SwanSongSupportBundleSnapshot: Codable, Equatable, Sendable {
    let schema: String
    let appVersion: String
    let appBuild: String
    let bundleIdentifier: String
    let sourceCommit: String
    let sourceTreeDirty: Bool
    let macOS: String
    let architecture: String
    let engine: String
    let safeMode: Bool
    let developerToolsEnabled: Bool
    let localControlEnabled: Bool
    let automaticUpdateChecks: Bool
    let automaticUpdateDownloads: Bool
    let betaUpdates: Bool
    let updaterConfigured: Bool
    let privacyManifestSHA256: String?
    let engineLockSHA256: String?
    let sparkleLockSHA256: String?

    @MainActor
    static func current(
        metadata: SwanSongMetadata,
        updater: SwanSongUpdater,
        safeMode: Bool
    ) -> Self {
        let info = Bundle.main.infoDictionary ?? [:]
        return Self(
            schema: "swansong-support-v1",
            appVersion: metadata.version,
            appBuild: metadata.build,
            bundleIdentifier: metadata.bundleIdentifier,
            sourceCommit: info["SwanSongSourceCommit"] as? String ?? "development",
            sourceTreeDirty: info["SwanSongSourceTreeDirty"] as? Bool ?? true,
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture,
            engine: metadata.engineDescription,
            safeMode: safeMode,
            developerToolsEnabled: UserDefaults.standard.bool(
                forKey: "SwanSong.debugToolsEnabled.v1"
            ),
            localControlEnabled: UserDefaults.standard.bool(
                forKey: SwanSongLocalMCPAccess.enabledDefaultsKey
            ),
            automaticUpdateChecks: updater.automaticallyChecksForUpdates,
            automaticUpdateDownloads: updater.automaticallyDownloadsUpdates,
            betaUpdates: updater.includesBetaUpdates,
            updaterConfigured: updater.isConfigured,
            privacyManifestSHA256: bundledHash(named: "PrivacyInfo", extension: "xcprivacy"),
            engineLockSHA256: bundledHash(named: "ares.lock", extension: "json"),
            sparkleLockSHA256: bundledHash(named: "sparkle.lock", extension: "json")
        )
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func bundledHash(named name: String, extension fileExtension: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum SwanSongSupportBundleExporter {
    @MainActor
    static func chooseDestinationAndExport(
        snapshot: SwanSongSupportBundleSnapshot
    ) async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save SwanSong Support Bundle"
        panel.nameFieldStringValue = "SwanSong-Support.zip"
        panel.prompt = "Create Bundle"
        panel.message = "This bundle contains only the summary shown in SwanSong—never games, saves, screenshots, project contents, or private paths."
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }
        return try await Task.detached(priority: .userInitiated) {
            try export(snapshot: snapshot, to: destination)
            return destination
        }.value
    }

    static func export(
        snapshot: SwanSongSupportBundleSnapshot,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "SwanSong-Support-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(snapshot).write(
            to: root.appendingPathComponent("diagnostics.json"),
            options: [.atomic]
        )
        let readme = """
        SwanSong Support Bundle

        This bundle was created only after its owner chose Create Support Bundle.
        It contains app, engine, update, and macOS version details plus hashes of
        bundled trust files. It does not contain game names, files, saves, states,
        screenshots, private paths, account details, or Translation Lab content.
        """
        try Data(readme.utf8).write(
            to: root.appendingPathComponent("README.txt"),
            options: [.atomic]
        )

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", root.path, destination.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [NSLocalizedDescriptionKey: detail.isEmpty
                    ? "The support bundle could not be created."
                    : detail]
            )
        }
    }
}
