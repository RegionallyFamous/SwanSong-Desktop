import AppKit
import Foundation
import SwanSongKit

/// Keeps one tiny, private launch marker so repeated startup failures can
/// automatically fall back to a minimal configuration.
final class SwanSongLaunchRecovery {
    static let forceSafeModeDefaultsKey = "SwanSong.forceSafeModeOnNextLaunch.v1"
    static let forceNormalModeDefaultsKey = "SwanSong.forceNormalModeOnNextLaunch.v1"
    static let currentSafeModeDefaultsKey = "SwanSong.currentSafeMode.v1"
    static let safeModeThreshold = 2

    private struct Record: Codable {
        let schema: Int
        var launchWasActive: Bool
        var consecutiveInterruptedLaunches: Int
    }

    let isSafeMode: Bool
    private let fileURL: URL
    private let userDefaults: UserDefaults

    init(
        fileURL: URL = SwanSongDataRootPolicy.defaultResolution().rootURL
            .appendingPathComponent("LaunchRecovery.json"),
        userDefaults: UserDefaults = .standard
    ) {
        self.fileURL = fileURL
        self.userDefaults = userDefaults

        let previous = Self.load(from: fileURL)
        var interruptionCount = previous?.launchWasActive == true
            ? (previous?.consecutiveInterruptedLaunches ?? 0) + 1
            : 0
        let forceNormal = userDefaults.bool(forKey: Self.forceNormalModeDefaultsKey)
        if forceNormal { interruptionCount = 0 }
        let forceSafe = userDefaults.bool(forKey: Self.forceSafeModeDefaultsKey)
        userDefaults.removeObject(forKey: Self.forceNormalModeDefaultsKey)
        userDefaults.removeObject(forKey: Self.forceSafeModeDefaultsKey)
        isSafeMode = !forceNormal
            && (forceSafe || interruptionCount >= Self.safeModeThreshold)
        userDefaults.set(isSafeMode, forKey: Self.currentSafeModeDefaultsKey)

        try? Self.save(
            Record(
                schema: 1,
                launchWasActive: true,
                consecutiveInterruptedLaunches: interruptionCount
            ),
            to: fileURL
        )
    }

    func markCleanTermination() {
        userDefaults.set(false, forKey: Self.currentSafeModeDefaultsKey)
        try? Self.save(
            Record(
                schema: 1,
                launchWasActive: false,
                consecutiveInterruptedLaunches: 0
            ),
            to: fileURL
        )
    }

    @MainActor
    static func restartInSafeMode() {
        UserDefaults.standard.set(true, forKey: forceSafeModeDefaultsKey)
        NSApp.terminate(nil)
    }

    @MainActor
    static func restartNormally() {
        UserDefaults.standard.set(true, forKey: forceNormalModeDefaultsKey)
        NSApp.terminate(nil)
    }

    private static func load(from url: URL) -> Record? {
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.schema == 1,
              record.consecutiveInterruptedLaunches >= 0,
              record.consecutiveInterruptedLaunches <= 100 else {
            return nil
        }
        return record
    }

    private static func save(_ record: Record, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let data = try JSONEncoder().encode(record)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
