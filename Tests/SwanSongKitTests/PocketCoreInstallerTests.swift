import Foundation
import Testing
@testable import SwanSongKit

struct PocketCoreInstallerTests {
    @Test
    func verifiesAuthorizedReleaseManifestAndChecksums() throws {
        let package = Data("official-pocket-package".utf8)
        let fixture = try releaseFixture(package: package)

        let release = try PocketCoreReleaseVerifier.verify(
            manifestData: fixture.manifest,
            checksumsData: fixture.checksums,
            githubTag: "v1.2.3"
        )

        #expect(release.version == "1.2.3")
        #expect(release.packageFilename == "RegionallyFamous.SwanSong_1.2.3_2026-07-16.zip")
        #expect(release.packageByteCount == package.count)
        #expect(release.packageSHA256 == PocketCoreReleaseVerifier.digest(package))
    }

    @Test
    func rejectsReleaseWithoutDistributionAuthorization() throws {
        let fixture = try releaseFixture(
            package: Data("not-authorized".utf8),
            distributionAuthorized: false
        )

        #expect(throws: PocketCoreInstallerError.self) {
            try PocketCoreReleaseVerifier.verify(
                manifestData: fixture.manifest,
                checksumsData: fixture.checksums,
                githubTag: "1.2.3"
            )
        }
    }

    @Test
    func recognizesPocketFileSystemsByStableKernelType() {
        #expect(PocketVolumeInspection.supportsPocketCardFileSystem("exfat"))
        #expect(PocketVolumeInspection.supportsPocketCardFileSystem("EXFAT"))
        #expect(PocketVolumeInspection.supportsPocketCardFileSystem("msdos"))
        #expect(!PocketVolumeInspection.supportsPocketCardFileSystem("apfs"))
        #expect(!PocketVolumeInspection.supportsPocketCardFileSystem("hfs"))
        #expect(!PocketVolumeInspection.supportsPocketCardFileSystem("FAT32"))
    }

    @Test
    func mountIdentityIsStableAcrossPathsOnTheSameVolume() throws {
        try withTemporaryDirectory { root in
            let child = root.appendingPathComponent("child", isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
            let rootIdentity = try PocketVolumeInspection.mountIdentity(at: root)
            let childIdentity = try PocketVolumeInspection.mountIdentity(at: child)

            #expect(rootIdentity.hasPrefix("fsid:"))
            #expect(rootIdentity == childIdentity)
        }
    }

    @Test
    func preparesCoreWithoutChangingGamesSavesOrOtherCores() throws {
        try withTemporaryDirectory { root in
            let release = releaseMetadata()
            let extracted = root.appendingPathComponent("package", isDirectory: true)
            try makePackage(at: extracted, release: release)
            let package = try PocketCorePackage(
                extractedDirectoryURL: extracted,
                release: release
            )

            let card = root.appendingPathComponent("POCKET", isDirectory: true)
            try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            let game = card.appendingPathComponent("Assets/wonderswan/common/my-game.ws")
            try FileManager.default.createDirectory(
                at: game.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("owned-game".utf8).write(to: game)
            let save = card.appendingPathComponent("Saves/wonderswan/other/save.sav")
            try FileManager.default.createDirectory(
                at: save.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("save".utf8).write(to: save)
            let otherCore = card.appendingPathComponent("Cores/Another.Core/core.json")
            try FileManager.default.createDirectory(
                at: otherCore.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("other".utf8).write(to: otherCore)

            let preparer = PocketCoreCardPreparer()
            let plan = try preparer.plan(package: package, destinationURL: card)
            #expect(plan.changedFileCount == package.files.count)
            let result = try preparer.apply(package: package, destinationURL: card)

            #expect(result.version == release.version)
            #expect(try Data(contentsOf: game) == Data("owned-game".utf8))
            #expect(try Data(contentsOf: save) == Data("save".utf8))
            #expect(try Data(contentsOf: otherCore) == Data("other".utf8))
            #expect(
                FileManager.default.fileExists(
                    atPath: card.appendingPathComponent(
                        "Cores/RegionallyFamous.SwanSong/wonderswan.rev"
                    ).path
                )
            )

            let secondPlan = try preparer.plan(package: package, destinationURL: card)
            #expect(secondPlan.changedFileCount == 0)
            #expect(secondPlan.unchangedFiles.count == package.files.count)
        }
    }

    @Test
    func rejectsPackageThatContainsAGame() throws {
        try withTemporaryDirectory { root in
            let release = releaseMetadata()
            try makePackage(at: root, release: release)
            try Data("game".utf8).write(
                to: root.appendingPathComponent("Assets/wonderswan/common/included.ws")
            )

            #expect(throws: PocketCoreInstallerError.self) {
                try PocketCorePackage(
                    extractedDirectoryURL: root,
                    release: release
                )
            }
        }
    }

    @Test
    func rejectsDestinationSymlinkInManagedPath() throws {
        try withTemporaryDirectory { root in
            let release = releaseMetadata()
            let extracted = root.appendingPathComponent("package", isDirectory: true)
            try makePackage(at: extracted, release: release)
            let package = try PocketCorePackage(
                extractedDirectoryURL: extracted,
                release: release
            )
            let card = root.appendingPathComponent("card", isDirectory: true)
            let elsewhere = root.appendingPathComponent("elsewhere", isDirectory: true)
            try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: card.appendingPathComponent("Cores"),
                withDestinationURL: elsewhere
            )

            #expect(throws: PocketCoreInstallerError.self) {
                try PocketCoreCardPreparer().plan(
                    package: package,
                    destinationURL: card
                )
            }
        }
    }

    @Test
    func rejectsInsufficientSpaceBeforeWritingAnything() throws {
        try withTemporaryDirectory { root in
            let release = releaseMetadata()
            let extracted = root.appendingPathComponent("package", isDirectory: true)
            try makePackage(at: extracted, release: release)
            let package = try PocketCorePackage(
                extractedDirectoryURL: extracted,
                release: release
            )
            let card = root.appendingPathComponent("card", isDirectory: true)
            try FileManager.default.createDirectory(at: card, withIntermediateDirectories: false)
            let marker = card.appendingPathComponent("keep.txt")
            try Data("untouched".utf8).write(to: marker)
            let preparer = PocketCoreCardPreparer(availableCapacity: { _ in 0 })

            #expect(throws: PocketCoreInstallerError.self) {
                try preparer.apply(package: package, destinationURL: card)
            }
            #expect(try Data(contentsOf: marker) == Data("untouched".utf8))
            #expect(
                !FileManager.default.fileExists(
                    atPath: card.appendingPathComponent("Cores").path
                )
            )
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: card.path)
                    == ["keep.txt"]
            )
        }
    }

    @Test
    func postWriteMismatchRestoresPreviousCoreAndRemovesNewFiles() throws {
        try withTemporaryDirectory { root in
            let release = releaseMetadata()
            let extracted = root.appendingPathComponent("package", isDirectory: true)
            try makePackage(at: extracted, release: release)
            let package = try PocketCorePackage(
                extractedDirectoryURL: extracted,
                release: release
            )
            let card = root.appendingPathComponent("card", isDirectory: true)
            let coreDirectory = card.appendingPathComponent(
                "Cores/RegionallyFamous.SwanSong",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: coreDirectory,
                withIntermediateDirectories: true
            )
            let coreJSON = coreDirectory.appendingPathComponent("core.json")
            let previousCore = Data("previous-core".utf8)
            try previousCore.write(to: coreJSON)
            let preparer = PocketCoreCardPreparer(
                availableCapacity: { _ in Int64.max },
                beforePostWriteVerification: { destination in
                    try Data("corrupted-after-write".utf8).write(
                        to: destination.appendingPathComponent(
                            "Cores/RegionallyFamous.SwanSong/core.json"
                        )
                    )
                }
            )

            #expect(throws: PocketCoreInstallerError.self) {
                try preparer.apply(package: package, destinationURL: card)
            }
            #expect(try Data(contentsOf: coreJSON) == previousCore)
            #expect(
                !FileManager.default.fileExists(
                    atPath: coreDirectory.appendingPathComponent("wonderswan.rev").path
                )
            )
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: card.path)
                    .allSatisfy { !$0.hasPrefix(".swansong-core-install-") }
            )
        }
    }

    private func releaseMetadata() -> PocketCoreReleaseMetadata {
        PocketCoreReleaseMetadata(
            version: "1.2.3",
            releaseDate: "2026-07-16",
            sourceCommit: String(repeating: "a", count: 40),
            packageFilename: "RegionallyFamous.SwanSong_1.2.3_2026-07-16.zip",
            packageByteCount: 100,
            packageSHA256: String(repeating: "b", count: 64)
        )
    }

    private func makePackage(
        at root: URL,
        release: PocketCoreReleaseMetadata
    ) throws {
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
        let coreJSON: [String: Any] = [
            "core": [
                "magic": "APF_VER_1",
                "metadata": [
                    "author": "RegionallyFamous",
                    "shortname": "SwanSong",
                    "url": PocketCoreReleaseMetadata.repositoryURL,
                    "version": release.version,
                    "date_release": release.releaseDate,
                ],
                "framework": [
                    "target_product": "Analogue Pocket",
                    "chip32_vm": "chip32.bin",
                ],
                "cores": [["filename": "wonderswan.rev"]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: coreJSON, options: [.sortedKeys])
            .write(to: core.appendingPathComponent("core.json"))
        for name in [
            "audio.json",
            "data.json",
            "input.json",
            "interact.json",
            "variants.json",
            "video.json",
        ] {
            try Data("{}".utf8).write(to: core.appendingPathComponent(name))
        }
        try Data("bitstream".utf8).write(to: core.appendingPathComponent("wonderswan.rev"))
        try Data("chip32".utf8).write(to: core.appendingPathComponent("chip32.bin"))
        try Data("{}".utf8).write(
            to: root.appendingPathComponent("Platforms/wonderswan.json")
        )
        try Data("art".utf8).write(
            to: root.appendingPathComponent("Platforms/_images/wonderswan.bin")
        )
        try Data().write(
            to: root.appendingPathComponent("Assets/wonderswan/common/.gitkeep")
        )
    }

    private func releaseFixture(
        package: Data,
        distributionAuthorized: Bool = true
    ) throws -> (manifest: Data, checksums: Data) {
        let filename = "RegionallyFamous.SwanSong_1.2.3_2026-07-16.zip"
        let packageDigest = PocketCoreReleaseVerifier.digest(package)
        let verification = Dictionary(
            uniqueKeysWithValues: [
                "both_quartus_audits_pass",
                "distinct_signed_quartus_runs",
                "rbf_and_build_id_reproduced",
                "hardware_qa_accepted",
                "known_title_compatibility_accepted",
                "release_evidence_v2_validated",
                "release_package_validated",
                "release_stage_applied_and_reverified",
                "corresponding_source_archived",
            ].map { ($0, true) }
        )
        let document: [String: Any] = [
            "release_manifest": [
                "magic": PocketCoreReleaseMetadata.manifestMagic,
                "core_id": PocketCoreReleaseMetadata.coreID,
                "repository_url": PocketCoreReleaseMetadata.repositoryURL,
                "version": "1.2.3",
                "date_release": "2026-07-16",
                "source_commit": String(repeating: "a", count: 40),
                "release_policy": [
                    "magic": "SWAN_SONG_RELEASE_POLICY_V2",
                    "core_id": PocketCoreReleaseMetadata.coreID,
                    "repository_url": PocketCoreReleaseMetadata.repositoryURL,
                    "identity_authorized": true,
                    "distribution_and_licensing_authorized": distributionAuthorized,
                ],
                "verification": verification,
                "artifacts": [
                    filename: [
                        "filename": filename,
                        "size": package.count,
                        "sha256": packageDigest,
                    ],
                ],
            ],
        ]
        let manifest = try JSONSerialization.data(
            withJSONObject: document,
            options: [.sortedKeys]
        )
        let checksums = Data(
            "\(packageDigest)  \(filename)\n\(PocketCoreReleaseVerifier.digest(manifest))  release-manifest.json\n"
                .utf8
        )
        return (manifest, checksums)
    }

    private func withTemporaryDirectory(
        _ body: (URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PocketCoreInstallerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
