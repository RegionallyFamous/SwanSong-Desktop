import Foundation
@testable import SwanSongKit
import XCTest

final class TranslationEvidencePrivateArtifactStoreTests: XCTestCase {
    func testBothPrivateArtifactKindsRoundTripIndependently() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let store = TranslationEvidenceStore()
        let payloads: [TranslationEvidencePrivateArtifact: Data] = [
            .textIntake: Data(#"{"schema":"swan-song-translation-text-intake-v1"}"#.utf8),
            .translationDraft: Data(#"{"schema":"swan-song-translation-draft-v1"}"#.utf8),
        ]

        for kind in TranslationEvidencePrivateArtifact.allCases {
            XCTAssertFalse(
                try store.privateArtifactExists(
                    kind,
                    evidence: fixture.evidence,
                    project: fixture.project
                )
            )
            XCTAssertNil(
                try store.loadPrivateArtifact(
                    kind,
                    evidence: fixture.evidence,
                    project: fixture.project
                )
            )

            let savedURL = try store.savePrivateArtifact(
                try XCTUnwrap(payloads[kind]),
                kind: kind,
                evidence: fixture.evidence,
                project: fixture.project
            )

            XCTAssertEqual(savedURL.lastPathComponent, kind.rawValue)
            XCTAssertEqual(
                savedURL.deletingLastPathComponent().resolvingSymlinksInPath(),
                fixture.evidence.artifact.directoryURL.resolvingSymlinksInPath()
            )
            XCTAssertTrue(
                try store.privateArtifactExists(
                    kind,
                    evidence: fixture.evidence,
                    project: fixture.project
                )
            )
            XCTAssertEqual(
                try store.loadPrivateArtifact(
                    kind,
                    evidence: fixture.evidence,
                    project: fixture.project
                ),
                payloads[kind]
            )
            XCTAssertEqual(
                try self.permissions(of: savedURL),
                0o600,
                "private sidecar permissions"
            )
            XCTAssertEqual(
                try self.permissions(of: savedURL.deletingLastPathComponent()),
                0o700,
                "private evidence-directory permissions"
            )
        }

        XCTAssertNotEqual(
            try store.privateArtifactURL(
                .textIntake,
                evidence: fixture.evidence,
                project: fixture.project
            ),
            try store.privateArtifactURL(
                .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        )
    }

    func testSaveRejectsEmptyAndOversizedArtifactsAndAcceptsExactLimit() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let store = TranslationEvidenceStore()
        XCTAssertThrowsError(
            try store.savePrivateArtifact(
                Data(),
                kind: .textIntake,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertInvalidProject($0) }

        XCTAssertThrowsError(
            try store.savePrivateArtifact(
                Data(count: TranslationEvidenceStore.maximumPrivateArtifactBytes + 1),
                kind: .textIntake,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertInvalidProject($0) }

        let boundaryPayload = Data(
            repeating: 0x5a,
            count: TranslationEvidenceStore.maximumPrivateArtifactBytes
        )
        try store.savePrivateArtifact(
            boundaryPayload,
            kind: .textIntake,
            evidence: fixture.evidence,
            project: fixture.project
        )
        XCTAssertEqual(
            try store.loadPrivateArtifact(
                .textIntake,
                evidence: fixture.evidence,
                project: fixture.project
            ),
            boundaryPayload
        )
    }

    func testLoadRejectsEmptyAndOversizedArtifactsAlreadyOnDisk() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let store = TranslationEvidenceStore()
        let url = try store.privateArtifactURL(
            .translationDraft,
            evidence: fixture.evidence,
            project: fixture.project
        )

        try Data().write(to: url)
        XCTAssertThrowsError(
            try store.loadPrivateArtifact(
                .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertInvalidProject($0) }

        try Data(
            count: TranslationEvidenceStore.maximumPrivateArtifactBytes + 1
        ).write(to: url)
        XCTAssertThrowsError(
            try store.loadPrivateArtifact(
                .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertInvalidProject($0) }
    }

    func testLoadRepairsPrivateArtifactPermissionsBeforeReturningData() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let store = TranslationEvidenceStore()
        let url = try store.privateArtifactURL(
            .textIntake,
            evidence: fixture.evidence,
            project: fixture.project
        )
        try Data("private".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o644))],
            ofItemAtPath: url.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.deletingLastPathComponent().path
        )

        XCTAssertEqual(
            try store.loadPrivateArtifact(
                .textIntake,
                evidence: fixture.evidence,
                project: fixture.project
            ),
            Data("private".utf8)
        )
        XCTAssertEqual(try permissions(of: url), 0o600)
        XCTAssertEqual(try permissions(of: url.deletingLastPathComponent()), 0o700)
    }

    func testRemovePrivateArtifactDeletesOnlyRequestedRegularSidecar() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let store = TranslationEvidenceStore()
        try store.savePrivateArtifact(
            Data("source".utf8),
            kind: .textIntake,
            evidence: fixture.evidence,
            project: fixture.project
        )
        try store.savePrivateArtifact(
            Data("target".utf8),
            kind: .translationDraft,
            evidence: fixture.evidence,
            project: fixture.project
        )

        XCTAssertTrue(
            try store.removePrivateArtifact(
                .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        )
        XCTAssertFalse(
            try store.removePrivateArtifact(
                .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        )
        XCTAssertEqual(
            try store.loadPrivateArtifact(
                .textIntake,
                evidence: fixture.evidence,
                project: fixture.project
            ),
            Data("source".utf8)
        )
    }

    func testRemovePrivateArtifactRejectsSymlinkedSidecar() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let store = TranslationEvidenceStore()
        let outside = fixture.root.appendingPathComponent("outside-draft.json")
        try Data("outside".utf8).write(to: outside)
        let sidecar = try store.privateArtifactURL(
            .translationDraft,
            evidence: fixture.evidence,
            project: fixture.project
        )
        try FileManager.default.createSymbolicLink(
            atPath: sidecar.path,
            withDestinationPath: outside.path
        )

        XCTAssertThrowsError(
            try store.removePrivateArtifact(
                .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertUnsafePath($0) }
        XCTAssertEqual(try Data(contentsOf: outside), Data("outside".utf8))
    }

    func testPrivateArtifactOperationsRejectDanglingSymlinkAsPresentUnsafeNode() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let store = TranslationEvidenceStore()
        let sidecar = try store.privateArtifactURL(
            .translationDraft,
            evidence: fixture.evidence,
            project: fixture.project
        )
        let missing = fixture.root.appendingPathComponent("missing-target.json")
        try FileManager.default.createSymbolicLink(
            atPath: sidecar.path,
            withDestinationPath: missing.path
        )

        XCTAssertThrowsError(
            try store.privateArtifactExists(
                .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertUnsafePath($0) }
        XCTAssertThrowsError(
            try store.loadPrivateArtifact(
                .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertUnsafePath($0) }
        XCTAssertThrowsError(
            try store.savePrivateArtifact(
                Data("replacement".utf8),
                kind: .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertUnsafePath($0) }
        XCTAssertThrowsError(
            try store.removePrivateArtifact(
                .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertUnsafePath($0) }
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: sidecar.path))
    }

    func testPrivateArtifactOperationsRejectHardLinkedSidecarWithoutChangingSource() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let store = TranslationEvidenceStore()
        let outside = fixture.root.appendingPathComponent("outside-hard-link.json")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o644))],
            ofItemAtPath: outside.path
        )
        let sidecar = try store.privateArtifactURL(
            .translationDraft,
            evidence: fixture.evidence,
            project: fixture.project
        )
        try FileManager.default.linkItem(at: outside, to: sidecar)

        XCTAssertThrowsError(
            try store.loadPrivateArtifact(
                .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertUnsafePath($0) }
        XCTAssertThrowsError(
            try store.savePrivateArtifact(
                Data("replacement".utf8),
                kind: .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertUnsafePath($0) }
        XCTAssertThrowsError(
            try store.removePrivateArtifact(
                .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertUnsafePath($0) }
        XCTAssertEqual(try Data(contentsOf: outside), Data("outside".utf8))
        XCTAssertEqual(try permissions(of: outside), 0o644)
    }

    func testEvidenceMustBeDirectlyInsideThisProjectsLabDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let store = TranslationEvidenceStore()
        let nestedDirectory = fixture.project.rootURL
            .appendingPathComponent("analysis/swan-song-lab/nested", isDirectory: true)
            .appendingPathComponent("capture-detached", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nestedDirectory,
            withIntermediateDirectories: true
        )
        let nestedEvidence = evidence(
            rebinding: fixture.evidence,
            to: nestedDirectory
        )

        XCTAssertThrowsError(
            try store.privateArtifactURL(
                .textIntake,
                evidence: nestedEvidence,
                project: fixture.project
            )
        ) { self.assertUnsafePath($0) }

        let secondFixture = try Fixture()
        defer { secondFixture.remove() }
        XCTAssertThrowsError(
            try store.privateArtifactURL(
                .textIntake,
                evidence: fixture.evidence,
                project: secondFixture.project
            )
        ) { self.assertUnsafePath($0) }
    }

    func testPrivateArtifactOperationsRejectSymlinkedCaptureDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let capture = fixture.evidence.artifact.directoryURL
        let relocated = fixture.project.rootURL
            .appendingPathComponent("relocated-capture", isDirectory: true)
        try FileManager.default.moveItem(at: capture, to: relocated)
        try FileManager.default.createSymbolicLink(
            atPath: capture.path,
            withDestinationPath: relocated.path
        )

        XCTAssertThrowsError(
            try TranslationEvidenceStore().privateArtifactExists(
                .textIntake,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertUnsafePath($0) }
    }

    func testPrivateArtifactOperationsRejectSymlinkedAnalysisAncestor() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let analysis = fixture.project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
        let relocated = fixture.project.rootURL
            .appendingPathComponent("relocated-analysis", isDirectory: true)
        try FileManager.default.moveItem(at: analysis, to: relocated)
        try FileManager.default.createSymbolicLink(
            atPath: analysis.path,
            withDestinationPath: relocated.path
        )

        XCTAssertThrowsError(
            try TranslationEvidenceStore().loadPrivateArtifact(
                .translationDraft,
                evidence: fixture.evidence,
                project: fixture.project
            )
        ) { self.assertUnsafePath($0) }
    }

    func testPrivateArtifactOperationsRejectNonDirectoryCaptureAndAncestor() throws {
        do {
            let fixture = try Fixture()
            defer { fixture.remove() }

            let capture = fixture.evidence.artifact.directoryURL
            try FileManager.default.removeItem(at: capture)
            try Data("not a directory".utf8).write(to: capture)

            XCTAssertThrowsError(
                try TranslationEvidenceStore().savePrivateArtifact(
                    Data("private".utf8),
                    kind: .textIntake,
                    evidence: fixture.evidence,
                    project: fixture.project
                )
            ) { self.assertUnsafePath($0) }
        }

        do {
            let fixture = try Fixture()
            defer { fixture.remove() }

            let analysis = fixture.project.rootURL
                .appendingPathComponent("analysis", isDirectory: true)
            try FileManager.default.removeItem(at: analysis)
            try Data("not a directory".utf8).write(to: analysis)

            XCTAssertThrowsError(
                try TranslationEvidenceStore().savePrivateArtifact(
                    Data("private".utf8),
                    kind: .translationDraft,
                    evidence: fixture.evidence,
                    project: fixture.project
                )
            ) { self.assertUnsafePath($0) }
        }
    }

    private func evidence(
        rebinding source: TranslationEvidenceSummary,
        to directory: URL
    ) -> TranslationEvidenceSummary {
        let artifact = TranslationEvidenceArtifact(
            name: directory.lastPathComponent,
            directoryURL: directory,
            manifestURL: directory.appendingPathComponent("manifest.json"),
            frameURL: directory.appendingPathComponent("frame.png"),
            stateURL: directory.appendingPathComponent("runtime.state"),
            internalRAMURL: directory.appendingPathComponent("ram.bin")
        )
        return TranslationEvidenceSummary(
            artifact: artifact,
            manifest: source.manifest,
            framePNG: source.framePNG,
            createdAt: source.createdAt,
            integrityIssue: source.integrityIssue,
            review: source.review,
            reviewIssue: source.reviewIssue
        )
    }

    private func assertUnsafePath(
        _ error: Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case TranslationLabError.unsafePath = error else {
            return XCTFail("Expected unsafePath, got \(error)", file: file, line: line)
        }
    }

    private func assertInvalidProject(
        _ error: Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case TranslationLabError.invalidProject = error else {
            return XCTFail("Expected invalidProject, got \(error)", file: file, line: line)
        }
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }
}

private final class Fixture {
    let root: URL
    let project: TranslationProject
    let evidence: TranslationEvidenceSummary

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.root = root

        let projectDirectory = root
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("private-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("bin/wstrans.mjs"))
        try FileManager.default.createDirectory(
            at: projectDirectory.appendingPathComponent("rom", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data([0x53, 0x57, 0x41, 0x4e]).write(
            to: projectDirectory.appendingPathComponent("rom/original.ws")
        )
        try Data(
            #"{"game":{"title":"Private Artifact Fixture","platform":"WonderSwan Color","sourceLanguage":"Japanese","targetLanguage":"English"},"rom":{"original":"rom/original.ws","patched":"rom/patched.ws"}}"#.utf8
        ).write(to: projectDirectory.appendingPathComponent("project.json"))

        let project = try TranslationProject(projectDirectory: projectDirectory)
        self.project = project
        let store = TranslationEvidenceStore()
        _ = try store.capture(
            TranslationEvidenceInput(
                project: project,
                role: .original,
                romURL: project.originalROMURL,
                romFooterChecksum: 0,
                backend: "private-artifact-test",
                frameNumber: 1,
                framePNG: Data([0x89, 0x50, 0x4e, 0x47]),
                state: Data([0x01]),
                internalRAM: Data([0x02]),
                route: nil
            )
        )
        self.evidence = try XCTUnwrap(store.listEvidence(project: project).first)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
