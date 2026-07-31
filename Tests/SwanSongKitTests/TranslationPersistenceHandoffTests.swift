import Foundation
@testable import SwanSongKit
import Testing

@Suite(.serialized)
struct TranslationPersistenceHandoffTests {
    @Test
    func authenticatesLegacyPairAndSealsOneObjectWithTwoExactPrivateClones() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let report = try TranslationPersistenceHandoffStore.seal(
            project: fixture.project,
            request: fixture.request,
            runtime: fixture.runtime()
        )

        #expect(report.isComplete)
        #expect(report.isNonempty)
        #expect(report.clonesAreByteIdentical)
        #expect(report.regionCount == 1)
        #expect(report.persistencePayloadByteCount == 32 * 1_024)
        #expect(report.nonzeroPayloadByteCount > 0)
        #expect(report.nonFFPayloadByteCount > 0)
        #expect(report.clones.map(\.consumer) == [.load, .continue])
        #expect(Set(report.clones.map(\.identity)).count == 2)
        #expect(report.clones.allSatisfy { $0.objectSHA256 == report.persistenceSHA256 })

        let artifact = try #require(try fixture.handoffArtifacts().first)
        let sealed = try Data(contentsOf: artifact.appendingPathComponent("sealed.persistence"))
        let load = try Data(contentsOf: artifact.appendingPathComponent("load.persistence"))
        let `continue` = try Data(
            contentsOf: artifact.appendingPathComponent("continue.persistence")
        )
        #expect(sealed == load)
        #expect(load == `continue`)
        #expect(sha256(sealed) == report.persistenceSHA256)
        for name in ["sealed.persistence", "load.persistence", "continue.persistence", "manifest.json"] {
            #expect(try permissions(artifact.appendingPathComponent(name)) == 0o600)
        }
        let reportJSON = String(decoding: try encoded(report), as: UTF8.self)
        #expect(!reportJSON.contains(fixture.root.path))
        #expect(!reportJSON.contains(".persistence"))
    }

    @Test
    func rejectsTamperedRuntimeStateWithoutPublishing() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePrivate(Data([0x99, 0x02, 0x03]), to: fixture.stateURL)

        #expect(throws: Error.self) {
            _ = try TranslationPersistenceHandoffStore.seal(
                project: fixture.project,
                request: fixture.request,
                runtime: fixture.runtime()
            )
        }
        #expect(try fixture.handoffArtifacts().isEmpty)
    }

    @Test
    func rejectsEmptyAndIncompletePersistenceWithoutPublishing() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let empty = fixture.runtime(persistence: EnginePersistence())
        #expect(throws: Error.self) {
            _ = try TranslationPersistenceHandoffStore.seal(
                project: fixture.project,
                request: fixture.request,
                runtime: empty
            )
        }
        #expect(try fixture.handoffArtifacts().isEmpty)

        let incomplete = fixture.runtime(
            persistence: EnginePersistence(regions: [.cartridgeRAM: Data([0x12])])
        )
        #expect(throws: Error.self) {
            _ = try TranslationPersistenceHandoffStore.seal(
                project: fixture.project,
                request: fixture.request,
                runtime: incomplete
            )
        }
        #expect(try fixture.handoffArtifacts().isEmpty)
    }

    @Test
    func rejectsNonPrivateAndSymlinkInputs() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: fixture.planURL.path
        )
        #expect(throws: Error.self) {
            _ = try TranslationPersistenceHandoffStore.seal(
                project: fixture.project,
                request: fixture.request,
                runtime: fixture.runtime()
            )
        }
        #expect(try fixture.handoffArtifacts().isEmpty)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fixture.planURL.path
        )
        let original = fixture.planURL.deletingLastPathComponent()
            .appendingPathComponent("plan.original.json")
        try FileManager.default.moveItem(at: fixture.planURL, to: original)
        try FileManager.default.createSymbolicLink(at: fixture.planURL, withDestinationURL: original)
        #expect(throws: Error.self) {
            _ = try TranslationPersistenceHandoffStore.seal(
                project: fixture.project,
                request: fixture.request,
                runtime: fixture.runtime()
            )
        }
        #expect(try fixture.handoffArtifacts().isEmpty)
    }

    @Test
    func removesPartialPublicationAndRefusesOutputOverwrite() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let interrupted = fixture.runtime { completed in
            if completed == 2 { throw TestFailure.interruptedPublication }
        }
        #expect(throws: Error.self) {
            _ = try TranslationPersistenceHandoffStore.seal(
                project: fixture.project,
                request: fixture.request,
                runtime: interrupted
            )
        }
        #expect(try fixture.handoffArtifacts().isEmpty)
        let outputRoot = fixture.outputRoot
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: outputRoot,
            includingPropertiesForKeys: nil
        )) ?? []
        #expect(entries.isEmpty)

        try FileManager.default.removeItem(at: outputRoot)
        let sentinel = Data("do-not-overwrite".utf8)
        try fixture.writePrivate(sentinel, to: outputRoot)
        #expect(throws: Error.self) {
            _ = try TranslationPersistenceHandoffStore.seal(
                project: fixture.project,
                request: fixture.request,
                runtime: fixture.runtime()
            )
        }
        #expect(try Data(contentsOf: outputRoot) == sentinel)
    }

    @Test
    func runsIndependentLoadAndContinueConsumersFromTheirExactClones() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let seal = try TranslationPersistenceHandoffStore.seal(
            project: fixture.project,
            request: fixture.request,
            runtime: fixture.runtime()
        )
        for consumer in [
            TranslationPersistenceHandoffConsumer.load,
            TranslationPersistenceHandoffConsumer.continue,
        ] {
            let clone = try #require(seal.clones.first { $0.consumer == consumer })
            let request = fixture.consumerRequest(
                seal: seal,
                cloneIdentity: clone.identity,
                consumer: consumer
            )
            let report = try TranslationPersistenceHandoffStore.captureConsumer(
                project: fixture.project,
                request: request,
                runtime: fixture.consumerRuntime()
            )
            #expect(report.consumer == consumer)
            #expect(report.cloneIdentity == clone.identity)
            #expect(UUID(uuidString: report.consumerCaptureIdentity) != nil)
            #expect(report.persistenceSHA256 == seal.persistenceSHA256)
            #expect(report.finalFrameNumber == 3)
            #expect(report.audio.emulatedFrameCount == 3)
            #expect(report.audio.nonzeroSamples > 0)
        }
        let artifacts = try fixture.consumerArtifacts()
        #expect(artifacts.count == 2)
        for artifact in artifacts {
            for name in ["plan.json", "frame.png", "audio.wav", "manifest.json"] {
                #expect(try permissions(artifact.appendingPathComponent(name)) == 0o600)
            }
        }
    }

    @Test
    func consumerRejectsWrongClonePurposeAndTamperedObject() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let seal = try TranslationPersistenceHandoffStore.seal(
            project: fixture.project,
            request: fixture.request,
            runtime: fixture.runtime()
        )
        let load = try #require(seal.clones.first { $0.consumer == .load })
        let wrongPurpose = fixture.consumerRequest(
            seal: seal,
            cloneIdentity: load.identity,
            consumer: .continue
        )
        #expect(throws: Error.self) {
            _ = try TranslationPersistenceHandoffStore.captureConsumer(
                project: fixture.project,
                request: wrongPurpose,
                runtime: fixture.consumerRuntime()
            )
        }
        #expect(try fixture.consumerArtifacts().isEmpty)

        let handoff = try #require(try fixture.handoffArtifacts().first)
        let cloneURL = handoff.appendingPathComponent("load.persistence")
        var tampered = try Data(contentsOf: cloneURL)
        tampered[tampered.startIndex] ^= 0xff
        try fixture.writePrivate(tampered, to: cloneURL)
        let request = fixture.consumerRequest(
            seal: seal,
            cloneIdentity: load.identity,
            consumer: .load
        )
        #expect(throws: Error.self) {
            _ = try TranslationPersistenceHandoffStore.captureConsumer(
                project: fixture.project,
                request: request,
                runtime: fixture.consumerRuntime()
            )
        }
        #expect(try fixture.consumerArtifacts().isEmpty)
    }

    @Test
    func consumerRemovesPartialPublicationOnFailure() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let seal = try TranslationPersistenceHandoffStore.seal(
            project: fixture.project,
            request: fixture.request,
            runtime: fixture.runtime()
        )
        let load = try #require(seal.clones.first { $0.consumer == .load })
        let request = fixture.consumerRequest(
            seal: seal,
            cloneIdentity: load.identity,
            consumer: .load
        )
        #expect(throws: Error.self) {
            _ = try TranslationPersistenceHandoffStore.captureConsumer(
                project: fixture.project,
                request: request,
                runtime: fixture.consumerRuntime { completed in
                    if completed == 2 { throw TestFailure.interruptedPublication }
                }
            )
        }
        #expect(try fixture.consumerArtifacts().isEmpty)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: fixture.consumerOutputRoot,
            includingPropertiesForKeys: nil
        )) ?? []
        #expect(entries.isEmpty)
    }
}

private enum TestFailure: Error {
    case interruptedPublication
}

private final class Fixture: @unchecked Sendable {
    let root: URL
    let project: TranslationProject
    let request: TranslationPersistenceHandoffRequest
    let stateURL: URL
    let planURL: URL

    var outputRoot: URL {
        project.rootURL.appendingPathComponent(
            "analysis/swan-song-lab/persistence-handoffs",
            isDirectory: true
        )
    }

    var consumerOutputRoot: URL {
        project.rootURL.appendingPathComponent(
            "analysis/swan-song-lab/persistence-consumers",
            isDirectory: true
        )
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-Persistence-Handoff-Tests-\(UUID().uuidString)",
            isDirectory: true
        )
        let projectRoot = root.appendingPathComponent("projects/fixture", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("{}\n".utf8).write(to: root.appendingPathComponent("package.json"))
        try Data("// fixture\n".utf8).write(to: root.appendingPathComponent("bin/wstrans.mjs"))
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let projectData = Data(
            """
            {
              "game": {
                "title": "Synthetic Persistence Fixture",
                "platform": "WonderSwan Color",
                "sourceLanguage": "Japanese",
                "targetLanguage": "English"
              },
              "rom": {
                "original": "rom/original.wsc",
                "patched": "build/patched.wsc"
              }
            }
            """.utf8
        )
        let projectManifestURL = projectRoot.appendingPathComponent("project.json")
        try projectData.write(to: projectManifestURL)
        project = try TranslationProject(projectDirectory: projectRoot)

        let analysis = projectRoot.appendingPathComponent("analysis", isDirectory: true)
        let lab = analysis.appendingPathComponent("swan-song-lab", isDirectory: true)
        let sessions = lab.appendingPathComponent("observed-sessions", isDirectory: true)
        let pairs = lab.appendingPathComponent("pairs", isDirectory: true)
        let sessionID = UUID().uuidString.lowercased()
        let sessionDirectory = sessions.appendingPathComponent(
            "session-\(sessionID)", isDirectory: true
        )
        let pairDirectory = pairs.appendingPathComponent("pair-synthetic", isDirectory: true)
        let captureDirectory = lab.appendingPathComponent(
            "capture-synthetic-patched", isDirectory: true
        )
        for directory in [analysis, lab, sessions, pairs, sessionDirectory, pairDirectory, captureDirectory] {
            try createPrivateDirectory(directory)
        }

        let rom = makeROM()
        try createPrivateDirectory(projectRoot.appendingPathComponent("rom", isDirectory: true))
        try createPrivateDirectory(projectRoot.appendingPathComponent("build", isDirectory: true))
        try writePrivateFixture(rom, to: project.originalROMURL)
        try writePrivateFixture(rom, to: project.patchedROMURL)
        let candidate = digest(rom)
        let metadata = try EngineSession.inspect(rom: rom)
        let engine = TranslationRouteEngineIdentity(
            backend: "ares",
            buildID: "synthetic-handoff-swan-abi10"
        )
        let engineSHA256 = sha256(try encoded(engine))
        let rtc = TranslationRouteRTCContext.proof
        let rtcSHA256 = sha256(try encoded(rtc))
        let persistenceSHA256 = sha256(
            Data(TranslationRouteStartContext.isolatedPersistencePolicy.utf8)
        )
        let start = TranslationRouteStartContext(
            hardwareModel: .wonderSwanColor,
            firmware: TranslationRouteFirmware(
                source: .openIPL,
                identifier: WonderSwanOpenIPL.identifier
            ),
            engine: engine,
            rtc: rtc
        )
        let frameNumber: UInt64 = 3
        let route = try TranslationRoute(
            recordedFrom: .original,
            sourceROM: candidate,
            start: start,
            totalFrames: frameNumber,
            events: [TranslationRouteEvent(frameIndex: 0, inputMask: 0)],
            checkpoint: TranslationRouteCheckpoint(
                frameIndex: frameNumber - 1,
                width: 224,
                height: 144,
                orientation: .horizontal,
                sha256: String(repeating: "1", count: 64)
            )
        )
        let plan = TranslationFrameInputPlan(
            totalFrames: frameNumber,
            events: [TranslationFrameInputPlanEvent(frameIndex: 0, inputs: [])]
        )
        let routeData = try encoded(route)
        let planData = try encoded(plan)
        let routeURL = captureDirectory.appendingPathComponent("route.json")
        planURL = pairDirectory.appendingPathComponent("plan.json")
        stateURL = captureDirectory.appendingPathComponent("runtime.state")
        let state = Data([0x01, 0x02, 0x03])
        try writePrivateFixture(routeData, to: routeURL)
        try writePrivateFixture(planData, to: planURL)
        try writePrivateFixture(state, to: stateURL)

        let capture = TranslationEvidenceManifest(
            schema: "swan-song-translation-evidence-v1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            projectTitle: project.title,
            romRole: .patched,
            romRelativePath: try project.relativePath(for: project.patchedROMURL),
            rom: candidate,
            romFooterChecksum: metadata.computedChecksum,
            backend: engine.backend,
            frameNumber: frameNumber,
            frame: TranslationArtifactDigest(
                byteCount: 1,
                sha256: String(repeating: "2", count: 64)
            ),
            gameFrameSHA256: String(repeating: "3", count: 64),
            state: digest(state),
            internalRAM: TranslationArtifactDigest(
                byteCount: 1,
                sha256: String(repeating: "4", count: 64)
            ),
            route: digest(routeData),
            isolatedPersistence: true
        )
        let captureData = try encoded(capture)
        let captureManifestURL = captureDirectory.appendingPathComponent("manifest.json")
        try writePrivateFixture(captureData, to: captureManifestURL)
        let originalLane = TranslationPersistedCaptureLane(
            role: .original,
            rom: candidate,
            romFooterChecksum: metadata.computedChecksum,
            frameNumber: frameNumber,
            nativeFrameSHA256: String(repeating: "1", count: 64),
            framePNG: TranslationArtifactDigest(
                byteCount: 1,
                sha256: String(repeating: "5", count: 64)
            ),
            evidenceName: "capture-synthetic-original",
            evidenceManifest: TranslationArtifactDigest(
                byteCount: 1,
                sha256: String(repeating: "6", count: 64)
            ),
            audio: nil
        )
        let patchedLane = TranslationPersistedCaptureLane(
            role: .patched,
            rom: candidate,
            romFooterChecksum: metadata.computedChecksum,
            frameNumber: frameNumber,
            nativeFrameSHA256: String(repeating: "3", count: 64),
            framePNG: TranslationArtifactDigest(
                byteCount: 1,
                sha256: String(repeating: "7", count: 64)
            ),
            evidenceName: captureDirectory.lastPathComponent,
            evidenceManifest: digest(captureData),
            audio: nil
        )
        let pair = TranslationPersistedCaptureManifest(
            schema: TranslationPersistedCaptureManifest.legacySchema,
            createdAt: Date(timeIntervalSince1970: 1_700_000_001),
            projectTitle: project.title,
            plan: digest(planData),
            route: digest(routeData),
            engine: engine,
            engineSHA256: engineSHA256,
            rtc: rtc,
            rtcSHA256: rtcSHA256,
            persistencePolicy: TranslationRouteStartContext.isolatedPersistencePolicy,
            persistenceSHA256: persistenceSHA256,
            original: originalLane,
            patched: patchedLane,
            pixelDiff: TranslationArtifactDigest(
                byteCount: 1,
                sha256: String(repeating: "8", count: 64)
            )
        )
        let pairData = try encodedLegacyPairWithoutAudioFields(pair)
        let pairManifestURL = pairDirectory.appendingPathComponent("manifest.json")
        try writePrivateFixture(pairData, to: pairManifestURL)
        let session = TranslationObservedPlayManifest(
            schema: TranslationObservedPlayManifest.currentSchema,
            sessionID: sessionID,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_002),
            status: .finished,
            role: .patched,
            hardwareModel: TranslationRouteHardwareModel.wonderSwanColor.rawValue,
            cumulativeFrames: frameNumber,
            scheduledInputTransitions: plan.events.count,
            scheduledInputFrames: 0,
            plan: digest(planData),
            rom: candidate,
            romFooterChecksum: metadata.computedChecksum,
            engine: engine,
            engineSHA256: engineSHA256,
            rtc: rtc,
            rtcSHA256: rtcSHA256,
            persistencePolicy: TranslationRouteStartContext.isolatedPersistencePolicy,
            persistenceSHA256: persistenceSHA256,
            finalCaptureManifestSHA256: sha256(pairData)
        )
        let sessionData = try encoded(session)
        let sessionManifestURL = sessionDirectory.appendingPathComponent("manifest.json")
        try writePrivateFixture(sessionData, to: sessionManifestURL)

        request = TranslationPersistenceHandoffRequest(
            projectManifest: .init(url: projectManifestURL, digest: digest(projectData)),
            sessionManifest: .init(url: sessionManifestURL, digest: digest(sessionData)),
            plan: .init(url: planURL, digest: digest(planData)),
            route: .init(url: routeURL, digest: digest(routeData)),
            runtimeState: .init(url: stateURL, digest: digest(state)),
            captureManifest: .init(url: captureManifestURL, digest: digest(captureData)),
            pairManifest: .init(url: pairManifestURL, digest: digest(pairData)),
            role: .patched,
            candidate: candidate,
            sessionID: sessionID,
            frameNumber: frameNumber,
            engine: engine,
            engineSHA256: engineSHA256,
            rtc: rtc,
            rtcSHA256: rtcSHA256
        )
    }

    func runtime(
        persistence: EnginePersistence = EnginePersistence(
            regions: [
                .cartridgeRAM: Data((0..<(32 * 1_024)).map { UInt8(($0 % 251) + 1) }),
            ]
        ),
        publicationCheckpoint: @escaping @Sendable (Int) throws -> Void = { _ in }
    ) -> TranslationPersistenceHandoffStore.Runtime {
        TranslationPersistenceHandoffStore.Runtime(
            capture: { _, _, _, _, _ in persistence },
            verifyStaging: { staged, _, _, _, _ in
                guard staged.regions == persistence.regions else {
                    throw TestFailure.interruptedPublication
                }
            },
            publicationCheckpoint: publicationCheckpoint
        )
    }

    func consumerRequest(
        seal: TranslationPersistenceHandoffReport,
        cloneIdentity: String,
        consumer: TranslationPersistenceHandoffConsumer
    ) -> TranslationPersistenceHandoffConsumerRequest {
        TranslationPersistenceHandoffConsumerRequest(
            sealIdentity: seal.sealIdentity,
            sealManifestSHA256: seal.sealManifestSHA256,
            cloneIdentity: cloneIdentity,
            consumer: consumer,
            plan: request.plan
        )
    }

    func consumerRuntime(
        publicationCheckpoint: @escaping @Sendable (Int) throws -> Void = { _ in }
    ) -> TranslationPersistenceHandoffStore.ConsumerRuntime {
        TranslationPersistenceHandoffStore.ConsumerRuntime(
            execute: { _, _, plan, _, _, _ in
                var collector = try TranslationCapturePlanAudioCollector(
                    expectedFrames: plan.totalFrames
                )
                for frameIndex in 0..<plan.totalFrames {
                    try collector.append(
                        EngineAudioBatch(
                            interleavedSamples: [0.25, -0.25],
                            channels: 2,
                            sampleRate: 48_000
                        ),
                        frameIndex: frameIndex
                    )
                }
                return TranslationPersistenceHandoffStore.ConsumerExecution(
                    frame: EngineVideoFrame(
                        pixels: Data(repeating: 0x44, count: 224 * 144 * 4),
                        width: 224,
                        height: 144,
                        strideBytes: 224 * 4,
                        isVertical: false,
                        number: plan.totalFrames
                    ),
                    audio: try collector.finish()
                )
            },
            publicationCheckpoint: publicationCheckpoint
        )
    }

    func handoffArtifacts() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: outputRoot.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: outputRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("handoff-") }
    }

    func consumerArtifacts() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: consumerOutputRoot.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: consumerOutputRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("consumer-") }
    }

    func writePrivate(_ data: Data, to url: URL) throws {
        try writePrivateFixture(data, to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func createPrivateDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: url.path
    )
}

private func writePrivateFixture(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: url.path
    )
}

private func makeROM() -> Data {
    var bytes = [UInt8](repeating: 0, count: 128 * 1_024)
    let footer = bytes.count - 16
    bytes[footer] = 0xea
    bytes[footer + 7] = 1
    bytes[footer + 10] = 0
    bytes[footer + 11] = 1
    bytes[footer + 12] = 0x04
    let checksum = bytes[..<(bytes.count - 2)].reduce(UInt16(0)) {
        $0 &+ UInt16($1)
    }
    bytes[bytes.count - 2] = UInt8(truncatingIfNeeded: checksum)
    bytes[bytes.count - 1] = UInt8(truncatingIfNeeded: checksum >> 8)
    return Data(bytes)
}

private func permissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

private func digest(_ data: Data) -> TranslationArtifactDigest {
    .init(byteCount: data.count, sha256: sha256(data))
}

private func sha256(_ data: Data) -> String {
    TranslationEvidenceStore.sha256(data)
}

private func encoded<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value)
}

private func encodedLegacyPairWithoutAudioFields(
    _ value: TranslationPersistedCaptureManifest
) throws -> Data {
    let encodedValue = try encoded(value)
    guard var object = try JSONSerialization.jsonObject(with: encodedValue) as? [String: Any],
          var original = object["original"] as? [String: Any],
          var patched = object["patched"] as? [String: Any] else {
        throw TestFailure.interruptedPublication
    }
    original.removeValue(forKey: "audio")
    patched.removeValue(forKey: "audio")
    object["original"] = original
    object["patched"] = patched
    return try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
}
