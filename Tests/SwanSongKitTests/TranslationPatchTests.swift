import Foundation
import SwanSongKit
import XCTest

final class TranslationPatchTests: XCTestCase {
    func testIPSAppliesLiteralAndRLERecordsAndRejectsTruncation() throws {
        let fixture = try TranslationPatchFixture()
        defer { fixture.remove() }

        XCTAssertEqual(
            try IPSPatch.apply(
                fixture.patch,
                to: fixture.original,
                expectedOutputByteCount: fixture.output.count
            ),
            fixture.output
        )
        XCTAssertThrowsError(
            try IPSPatch.apply(
                Data("PATCH".utf8),
                to: fixture.original,
                expectedOutputByteCount: fixture.original.count
            )
        ) { error in
            XCTAssertEqual(error as? TranslationPatchError, .malformedIPS)
        }
    }

    func testPackageInstallsSeparateVerifiedManagedGame() throws {
        let fixture = try TranslationPatchFixture()
        defer { fixture.remove() }
        let package = try TranslationPatchPackage(manifestURL: fixture.manifestURL)
        let managedStore = ManagedGameStore(
            rootURL: fixture.rootURL.appendingPathComponent("Games", isDirectory: true)
        )

        let result = try TranslationPatchInstaller(package: package).install(
            originalImage: fixture.originalImage,
            into: [],
            managedStore: managedStore
        )

        XCTAssertEqual(result.action, .installed)
        XCTAssertEqual(result.games.count, 1)
        let game = try XCTUnwrap(result.games.first)
        XCTAssertEqual(game.title, "Translation Fixture — English")
        XCTAssertEqual(game.translationPatchOrigin?.translationVersion, "1.0")
        XCTAssertEqual(
            game.translationPatchOrigin?.inputSHA256,
            ManagedGameStore.sha256(fixture.original)
        )
        XCTAssertEqual(
            try managedStore.load(try XCTUnwrap(game.managedROM)),
            fixture.output
        )
        XCTAssertEqual(fixture.original, fixture.originalSnapshot)

        let duplicate = try TranslationPatchInstaller(package: package).install(
            originalImage: fixture.originalImage,
            into: result.games,
            managedStore: managedStore
        )
        XCTAssertEqual(duplicate.action, .unchanged)
        XCTAssertEqual(duplicate.gameID, game.id)
        XCTAssertEqual(duplicate.games.count, 1)

        let managedURL = try managedStore.url(for: try XCTUnwrap(game.managedROM))
        let handle = try FileHandle(forWritingTo: managedURL)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data([0x99]))
        try handle.close()
        XCTAssertEqual(
            managedStore.health(of: try XCTUnwrap(game.managedROM)),
            .changed
        )
        let repaired = try TranslationPatchInstaller(package: package).install(
            originalImage: fixture.originalImage,
            into: result.games,
            managedStore: managedStore
        )
        XCTAssertEqual(repaired.action, .repaired)
        XCTAssertEqual(repaired.gameID, game.id)
        XCTAssertEqual(
            try managedStore.load(try XCTUnwrap(game.managedROM)),
            fixture.output
        )
    }

    func testInstallerRejectsWrongOriginalAndUnsafePatchPath() throws {
        let fixture = try TranslationPatchFixture()
        defer { fixture.remove() }
        let package = try TranslationPatchPackage(manifestURL: fixture.manifestURL)
        var wrongBytes = [UInt8](fixture.original)
        wrongBytes[50] = 1
        TranslationPatchFixture.repairChecksum(&wrongBytes)
        let wrongData = Data(wrongBytes)
        let wrongImage = LibraryGameImportImage(
            data: wrongData,
            suggestedTitle: "Wrong Revision",
            sourceFileName: "wrong.wsc",
            metadata: try GameROMValidationPolicy.validateLibraryImage(wrongData),
            sha256: ManagedGameStore.sha256(wrongData),
            hardwareModel: .wonderSwanColor
        )
        XCTAssertThrowsError(
            try TranslationPatchInstaller(package: package).install(
                originalImage: wrongImage,
                into: [],
                managedStore: ManagedGameStore(
                    rootURL: fixture.rootURL.appendingPathComponent(
                        "Wrong-Games",
                        isDirectory: true
                    )
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? TranslationPatchError,
                .originalSHA256Mismatch
            )
        }

        try fixture.writeManifest(patchPath: "../release/fixture.ips")
        XCTAssertThrowsError(
            try TranslationPatchPackage(manifestURL: fixture.manifestURL)
        ) { error in
            XCTAssertEqual(error as? TranslationPatchError, .unsafePatchPath)
        }
    }

    func testManifestAcceptsIntegerVersionAndSourceFreeReceipts() throws {
        let fixture = try TranslationPatchFixture()
        defer { fixture.remove() }
        let data = try Data(contentsOf: fixture.manifestURL)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["translationVersion"] = 6
        object["coverage"] = [
            "uniqueLocalizedUnits": 165,
            "unlocalizedActionable": 0,
        ]
        object["checks"] = [
            "nativeOneToOneReadabilityPassed": true,
            "ipsRoundtripExact": true,
        ]
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        ).write(to: fixture.manifestURL, options: [.atomic])

        let package = try TranslationPatchPackage(manifestURL: fixture.manifestURL)
        XCTAssertEqual(package.manifest.translationVersion, "6")
    }
}

private struct TranslationPatchFixture {
    let rootURL: URL
    let manifestURL: URL
    let patchURL: URL
    let original: Data
    let originalSnapshot: Data
    let output: Data
    let patch: Data
    let originalImage: LibraryGameImportImage

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-TranslationPatchTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let releaseDirectory = rootURL
            .appendingPathComponent("fixture", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
        try FileManager.default.createDirectory(
            at: releaseDirectory,
            withIntermediateDirectories: true
        )
        manifestURL = releaseDirectory.appendingPathComponent("release.json")
        patchURL = releaseDirectory.appendingPathComponent("fixture.ips")

        original = Self.makeROM()
        originalSnapshot = original
        var outputBytes = [UInt8](original)
        outputBytes[100] = 0x42
        outputBytes.replaceSubrange(200..<203, with: repeatElement(0x7f, count: 3))
        Self.repairChecksum(&outputBytes)
        output = Data(outputBytes)

        func offsetBytes(_ value: Int) -> [UInt8] {
            [
                UInt8(truncatingIfNeeded: value >> 16),
                UInt8(truncatingIfNeeded: value >> 8),
                UInt8(truncatingIfNeeded: value),
            ]
        }
        var patchData = Data("PATCH".utf8)
        patchData.append(contentsOf: offsetBytes(100))
        patchData.append(contentsOf: [0x00, 0x01, 0x42])
        patchData.append(contentsOf: offsetBytes(200))
        patchData.append(contentsOf: [0x00, 0x00, 0x00, 0x03, 0x7f])
        patchData.append(contentsOf: offsetBytes(outputBytes.count - 2))
        patchData.append(contentsOf: [
            0x00,
            0x02,
            outputBytes[outputBytes.count - 2],
            outputBytes[outputBytes.count - 1],
        ])
        patchData.append(Data("EOF".utf8))
        patch = patchData
        try patch.write(to: patchURL, options: [.atomic])

        let metadata = try GameROMValidationPolicy.validateLibraryImage(original)
        originalImage = LibraryGameImportImage(
            data: original,
            suggestedTitle: "Original Fixture",
            sourceFileName: "original.wsc",
            metadata: metadata,
            sha256: ManagedGameStore.sha256(original),
            hardwareModel: .wonderSwanColor
        )
        try writeManifest()
    }

    func writeManifest(patchPath: String = "release/fixture.ips") throws {
        let manifest: [String: Any] = [
            "schema": "fixture-distributable-release-v1",
            "status": "release-certified",
            "sourceFree": true,
            "releaseEligible": true,
            "title": "Translation Fixture",
            "platform": "WonderSwan Color",
            "revision": "FIXTURE-1",
            "translationVersion": "1.0",
            "input": [
                "byteCount": original.count,
                "sha256": ManagedGameStore.sha256(original),
            ],
            "patch": [
                "format": "IPS",
                "path": patchPath,
                "byteCount": patch.count,
                "sha256": ManagedGameStore.sha256(patch),
            ],
            "output": [
                "byteCount": output.count,
                "sha256": ManagedGameStore.sha256(output),
                "checksumValid": true,
            ],
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        ).write(to: manifestURL, options: [.atomic])
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    static func repairChecksum(_ bytes: inout [UInt8]) {
        let checksum = bytes[..<(bytes.count - 2)].reduce(UInt16(0)) {
            $0 &+ UInt16($1)
        }
        bytes[bytes.count - 2] = UInt8(truncatingIfNeeded: checksum)
        bytes[bytes.count - 1] = UInt8(truncatingIfNeeded: checksum >> 8)
    }

    private static func makeROM() -> Data {
        var bytes = [UInt8](repeating: 0, count: 128 * 1_024)
        let footer = bytes.count - 16
        bytes[footer] = 0xea
        bytes[footer + 7] = 1
        bytes[footer + 10] = 0
        bytes[footer + 11] = 1
        bytes[footer + 12] = 0x04
        repairChecksum(&bytes)
        return Data(bytes)
    }
}
