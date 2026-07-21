import Foundation
@testable import SwanSongApp
import XCTest

final class LaunchRecoveryAndSupportTests: XCTestCase {
    func testRepeatedInterruptedLaunchesEnterSafeModeAndCleanExitResetsIt() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("LaunchRecovery.json")
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "LaunchRecoveryTests.\(UUID().uuidString)")
        )

        XCTAssertFalse(SwanSongLaunchRecovery(fileURL: marker, userDefaults: defaults).isSafeMode)
        XCTAssertFalse(SwanSongLaunchRecovery(fileURL: marker, userDefaults: defaults).isSafeMode)
        let recovery = SwanSongLaunchRecovery(fileURL: marker, userDefaults: defaults)
        XCTAssertTrue(recovery.isSafeMode)

        recovery.markCleanTermination()
        XCTAssertFalse(SwanSongLaunchRecovery(fileURL: marker, userDefaults: defaults).isSafeMode)
    }

    func testSupportBundleContainsOnlyDeclaredSourceFreeSummary() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Support.zip")
        let extraction = root.appendingPathComponent("Extracted", isDirectory: true)
        let snapshot = SwanSongSupportBundleSnapshot(
            schema: "swansong-support-v1",
            appVersion: "0.7.0",
            appBuild: "13",
            bundleIdentifier: "com.regionallyfamous.swansong",
            sourceCommit: String(repeating: "a", count: 40),
            sourceTreeDirty: false,
            macOS: "macOS fixture",
            architecture: "arm64",
            engine: "fixture",
            safeMode: false,
            developerToolsEnabled: false,
            localControlEnabled: false,
            automaticUpdateChecks: false,
            automaticUpdateDownloads: false,
            betaUpdates: false,
            updaterConfigured: true,
            privacyManifestSHA256: String(repeating: "b", count: 64),
            engineLockSHA256: String(repeating: "c", count: 64),
            sparkleLockSHA256: String(repeating: "d", count: 64)
        )

        try SwanSongSupportBundleExporter.export(snapshot: snapshot, to: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        try FileManager.default.createDirectory(at: extraction, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", destination.path, extraction.path])

        let files = try FileManager.default.contentsOfDirectory(atPath: extraction.path).sorted()
        XCTAssertEqual(files, ["README.txt", "diagnostics.json"])
        let decoded = try JSONDecoder().decode(
            SwanSongSupportBundleSnapshot.self,
            from: Data(contentsOf: extraction.appendingPathComponent("diagnostics.json"))
        )
        XCTAssertEqual(decoded, snapshot)
        let combined = try files.map {
            try String(
                decoding: Data(contentsOf: extraction.appendingPathComponent($0)),
                as: UTF8.self
            )
        }.joined(separator: "\n")
        XCTAssertFalse(combined.contains("/Users/"))
        XCTAssertFalse(combined.contains("Secret Fixture Game"))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-RecoveryTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
