import Foundation
import XCTest
@testable import SwanSongApp

final class PocketCoreArchiveExtractorTests: XCTestCase {
    func testExtractsOrdinaryPocketScopedArchive() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        try makeScopedTree(at: source)
        let archive = root.appendingPathComponent("core.zip")
        try zip(source: source, archive: archive)
        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false)

        try PocketCoreArchiveExtractor.extract(archive: archive, to: extracted)

        XCTAssertEqual(
            try Data(
                contentsOf: extracted.appendingPathComponent(
                    "Cores/RegionallyFamous.SwanSong/core.json"
                )
            ),
            Data("{}".utf8)
        )
    }

    func testRejectsSymlinkBeforeExtraction() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        try makeScopedTree(at: source)
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent(
                "Cores/RegionallyFamous.SwanSong/escape"
            ),
            withDestinationURL: URL(fileURLWithPath: "/tmp")
        )
        let archive = root.appendingPathComponent("linked.zip")
        try zip(source: source, archive: archive, preserveLinks: true)
        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false)

        XCTAssertThrowsError(
            try PocketCoreArchiveExtractor.extract(archive: archive, to: extracted)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("link"))
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: extracted.appendingPathComponent(
                    "Cores/RegionallyFamous.SwanSong/escape"
                ).path
            )
        )
    }

    private func makeScopedTree(at root: URL) throws {
        let core = root.appendingPathComponent(
            "Cores/RegionallyFamous.SwanSong",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Assets/wonderswan/common", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: core, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Platforms/_images", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: core.appendingPathComponent("core.json"))
        try Data("{}".utf8).write(
            to: root.appendingPathComponent("Platforms/wonderswan.json")
        )
        try Data("art".utf8).write(
            to: root.appendingPathComponent("Platforms/_images/wonderswan.bin")
        )
    }

    private func zip(
        source: URL,
        archive: URL,
        preserveLinks: Bool = false
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = source
        process.arguments = [
            "-q",
            "-X",
            "-r",
            preserveLinks ? "-y" : nil,
            archive.path,
            "Assets",
            "Cores",
            "Platforms",
        ].compactMap { $0 }
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PocketCoreArchiveExtractorTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
