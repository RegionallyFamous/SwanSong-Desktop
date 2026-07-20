import CryptoKit
import Foundation
@testable import SwanSongKit
import XCTest

final class SwanSongAuthorizedProcessEnvironmentTests: XCTestCase {
    private var environment: [String: String] {
        [
            "LANG": "C",
            "LC_ALL": "C",
            "PATH": "/usr/bin:/bin",
            "SWAN_ARES_ENGINE_DIR": "/engine",
            "TZ": "UTC",
            "__CF_USER_TEXT_ENCODING": SwanSongAuthorizedProcessEnvironmentContract
                .expectedCFUserTextEncoding(),
        ]
    }

    func testPreservedPublicAuthorizationCrossLanguageCanonicalBytes() throws {
        let preservedEnvironment = [
            "LANG": "C",
            "LC_ALL": "C",
            "PATH": "/usr/bin:/bin",
            "SWAN_ARES_ENGINE_DIR":
                "/Users/nick/Documents/GitHub/SwanSong-Desktop/.engine/build-capability-v4",
            "TZ": "UTC",
            "__CF_USER_TEXT_ENCODING": "0x1F5:0x0:0x0",
        ]
        let javaScriptCanonical = Data((
            "{\"LANG\":\"C\",\"LC_ALL\":\"C\",\"PATH\":\"/usr/bin:/bin\"," +
            "\"SWAN_ARES_ENGINE_DIR\":" +
            "\"/Users/nick/Documents/GitHub/SwanSong-Desktop/.engine/build-capability-v4\"," +
            "\"TZ\":\"UTC\",\"__CF_USER_TEXT_ENCODING\":\"0x1F5:0x0:0x0\"}"
        ).utf8)
        let foundationCanonical = try JSONSerialization.data(
            withJSONObject: preservedEnvironment,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let hash: (Data) -> String = { data in
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let javaScriptDigest = hash(javaScriptCanonical)
        let foundationDigest = hash(foundationCanonical)
        let contractDigest = try SwanSongAuthorizedProcessEnvironmentContract
            .canonicalEnvironmentSHA256(preservedEnvironment)
        let javaScriptHex = javaScriptCanonical
            .map { String(format: "%02x", $0) }.joined()
        let foundationHex = foundationCanonical
            .map { String(format: "%02x", $0) }.joined()

        print("JS_CANONICAL_HEX=\(javaScriptHex)")
        print("JS_SHA256=\(javaScriptDigest)")
        print("FOUNDATION_CANONICAL_HEX=\(foundationHex)")
        print("FOUNDATION_SHA256=\(foundationDigest)")
        XCTAssertEqual(
            javaScriptDigest,
            "6ffa10648c07fc39c302cbd8d0335cfd5b3b2a6ebb02b88e08ce38e8330a8680"
        )
        XCTAssertEqual(contractDigest, javaScriptDigest)
        XCTAssertEqual(
            foundationDigest,
            "3a303bc18691a997b76b35c2c9a836aece638d39ab26120971613835d879111e"
        )
        XCTAssertNotEqual(javaScriptCanonical, foundationCanonical)
        XCTAssertThrowsError(
            try SwanSongAuthorizedProcessEnvironmentContract.validate(
                expectedEnvironment: preservedEnvironment,
                expectedEnvironmentSHA256: foundationDigest,
                canonicalEngineDirectory:
                    "/Users/nick/Documents/GitHub/SwanSong-Desktop/.engine/build-capability-v4",
                actualEnvironment: preservedEnvironment
            )
        )
    }

    func testCanonicalEnvironmentPinsJavaScriptCodeUnitOrdering() throws {
        let fixture = [
            "LANG": "C",
            "LC_ALL": "C",
            "PATH": "/usr/bin:/bin",
            "SWAN_ARES_ENGINE_DIR": "/engine",
            "TZ": "UTC",
            "__CF_USER_TEXT_ENCODING": "0x1F5:0x0:0x0",
        ]
        XCTAssertEqual(
            try SwanSongAuthorizedProcessEnvironmentContract
                .canonicalEnvironmentSHA256(fixture),
            "5115cca8bead847e36ef5ffe2930888680c2a74871e65e92cf8419eaed933b6f"
        )
    }

    func testCanonicalEnvironmentMatchesJavaScriptStringEscaping() throws {
        let fixture = [
            "A": "quote\" backslash\\ slash/ controls\u{08}\u{0c}\n\r\t\u{01} é 😀\u{2028}",
            "__": "line\u{2029}",
        ]
        let canonical = SwanSongAuthorizedProcessEnvironmentContract
            .canonicalEnvironmentJSON(fixture)
        XCTAssertEqual(
            canonical.map { String(format: "%02x", $0) }.joined(),
            "7b2241223a2271756f74655c22206261636b736c6173685c5c20736c6173682f" +
            "20636f6e74726f6c735c625c665c6e5c725c745c753030303120c3a920f09f" +
            "9880e280a8222c225f5f223a226c696e65e280a9227d"
        )
        XCTAssertEqual(
            try SwanSongAuthorizedProcessEnvironmentContract
                .canonicalEnvironmentSHA256(fixture),
            "b04ad2c9a4addb6f1bf3aaee5c59820b511a09d41bdacf91d29b19366e815035"
        )
    }

    func testCaptureEnvelopeUsesFinalizedV2AuthorizationSchemas() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SwanSongRouteRunner")
            .appendingPathComponent("AuthorizedCapturePlanEnvelope.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for schema in [
            "wstrans-swansong-capture-plan-bootstrap-capability-v2",
            "wstrans-swansong-capture-plan-authorization-v2",
            "swan-song-authorized-method-closure-v2",
        ] {
            XCTAssertTrue(source.contains("\"\(schema)\""), "missing \(schema)")
        }
        for staleSchema in [
            "wstrans-swansong-capture-plan-bootstrap-capability-v1",
            "wstrans-swansong-capture-plan-authorization-v1",
            "swan-song-authorized-method-closure-v1",
        ] {
            XCTAssertFalse(source.contains("\"\(staleSchema)\""), "retained \(staleSchema)")
        }
    }

    func testCommercialCaptureNativeGateIsCompleteBeforeExecution() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SwanSongRouteRunner")
            .appendingPathComponent("AuthorizedCapturePlanEnvelope.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for required in [
            "validateIsolatedEmptyPersistence(request[\"persistence\"])",
            "validateProtectedInputs(",
            "validateCommercialRequestTicket(",
            "translatedProject.toolkitURL",
            "requestTicketFile",
        ] {
            XCTAssertTrue(source.contains(required), "missing native gate: \(required)")
        }
        let prepare = try XCTUnwrap(source.range(of: "static func prepare("))
        let protected = try XCTUnwrap(source.range(of: "let protected = try validateProtectedInputs("))
        let ticket = try XCTUnwrap(source.range(of: "requestTicket = try validateCommercialRequestTicket("))
        let runner = try XCTUnwrap(source.range(of: "enum AuthorizedCapturePlanRunner"))
        let execute = try XCTUnwrap(source.range(of: "AuthorizedCapturePlanExecutor.run("))
        XCTAssertLessThan(prepare.lowerBound, protected.lowerBound)
        XCTAssertLessThan(protected.lowerBound, ticket.lowerBound)
        XCTAssertLessThan(ticket.lowerBound, runner.lowerBound)
        XCTAssertLessThan(runner.lowerBound, execute.lowerBound)
    }

    func testExactEnvironmentProducesHonestClosureAttestation() throws {
        let digest = try SwanSongAuthorizedProcessEnvironmentContract
            .canonicalEnvironmentSHA256(environment)
        XCTAssertEqual(digest.count, 64)
        XCTAssertEqual(
            SwanSongAuthorizedProcessEnvironmentContract.expectedCFUserTextEncoding(uid: 501),
            "0x1F5:0x0:0x0"
        )

        let observation = try SwanSongAuthorizedProcessEnvironmentContract.validate(
            expectedEnvironment: environment,
            expectedEnvironmentSHA256: digest,
            canonicalEngineDirectory: "/engine",
            actualEnvironment: environment
        )
        XCTAssertEqual(observation.environment, environment)
        XCTAssertEqual(observation.environmentSHA256, digest)

        let attestation = observation.closureAttestation
        XCTAssertEqual(attestation.keys.sorted(), [
            "activeSameUserRaceProtected", "environment", "environmentSHA256",
            "exclusiveLocalExecutionRequired", "preMainLoaderIdentityProven", "schema",
        ])
        XCTAssertEqual(
            attestation["schema"] as? String,
            "swan-song-authorized-process-execution-attestation-v1"
        )
        XCTAssertEqual(attestation["environment"] as? [String: String], environment)
        XCTAssertEqual(attestation["environmentSHA256"] as? String, digest)
        XCTAssertEqual(attestation["exclusiveLocalExecutionRequired"] as? Bool, true)
        XCTAssertEqual(attestation["activeSameUserRaceProtected"] as? Bool, false)
        XCTAssertEqual(attestation["preMainLoaderIdentityProven"] as? Bool, false)
    }

    func testRejectsMissingWrongOrExtraObservedCFEnvironment() throws {
        let digest = try SwanSongAuthorizedProcessEnvironmentContract
            .canonicalEnvironmentSHA256(environment)
        var missingCF = environment
        missingCF.removeValue(forKey: "__CF_USER_TEXT_ENCODING")
        var wrongCF = environment
        wrongCF["__CF_USER_TEXT_ENCODING"] = "0x0:0x0:0x0"
        var extra = environment
        extra["UNBOUND"] = "present"

        for actual in [missingCF, wrongCF, extra] {
            XCTAssertThrowsError(
                try SwanSongAuthorizedProcessEnvironmentContract.validate(
                    expectedEnvironment: environment,
                    expectedEnvironmentSHA256: digest,
                    canonicalEngineDirectory: "/engine",
                    actualEnvironment: actual
                )
            )
        }
    }

    func testRejectsAuthorizationValueDigestAndEngineDirectoryDrift() throws {
        let digest = try SwanSongAuthorizedProcessEnvironmentContract
            .canonicalEnvironmentSHA256(environment)
        var wrongPath = environment
        wrongPath["PATH"] = "/usr/bin:/bin:/usr/sbin"
        var missingCF = environment
        missingCF.removeValue(forKey: "__CF_USER_TEXT_ENCODING")
        var wrongCF = environment
        wrongCF["__CF_USER_TEXT_ENCODING"] = "0x0:0x0:0x0"

        XCTAssertThrowsError(
            try SwanSongAuthorizedProcessEnvironmentContract.validate(
                expectedEnvironment: wrongPath,
                expectedEnvironmentSHA256: digest,
                canonicalEngineDirectory: "/engine",
                actualEnvironment: wrongPath
            )
        )
        XCTAssertThrowsError(
            try SwanSongAuthorizedProcessEnvironmentContract.validate(
                expectedEnvironment: environment,
                expectedEnvironmentSHA256: String(repeating: "0", count: 64),
                canonicalEngineDirectory: "/engine",
                actualEnvironment: environment
            )
        )
        XCTAssertThrowsError(
            try SwanSongAuthorizedProcessEnvironmentContract.validate(
                expectedEnvironment: environment,
                expectedEnvironmentSHA256:
                    "4a4909bf1633ef6624177c903d04d28cbc08814e22863fbe24747c4423842ec4",
                canonicalEngineDirectory: "/engine",
                actualEnvironment: environment
            )
        )
        XCTAssertThrowsError(
            try SwanSongAuthorizedProcessEnvironmentContract.validate(
                expectedEnvironment: environment,
                expectedEnvironmentSHA256: digest,
                canonicalEngineDirectory: "/different-engine",
                actualEnvironment: environment
            )
        )
        for invalidExpected in [missingCF, wrongCF] {
            let invalidDigest = try SwanSongAuthorizedProcessEnvironmentContract
                .canonicalEnvironmentSHA256(invalidExpected)
            XCTAssertThrowsError(
                try SwanSongAuthorizedProcessEnvironmentContract.validate(
                    expectedEnvironment: invalidExpected,
                    expectedEnvironmentSHA256: invalidDigest,
                    canonicalEngineDirectory: "/engine",
                    actualEnvironment: invalidExpected
                )
            )
        }
    }

    func testFoundationChildObservesStableExactSixKeyEnvironment() throws {
        let bundle = Bundle(for: Self.self).bundleURL
        let observer = bundle.deletingLastPathComponent()
            .appendingPathComponent("SwanSongEnvironmentObserver")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: observer.path))

        var observations: [[String: [String: String]]] = []
        for _ in 0..<2 {
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            process.executableURL = observer
            process.currentDirectoryURL = observer.deletingLastPathComponent()
            process.environment = environment
            process.standardOutput = standardOutput
            process.standardError = standardError
            try process.run()
            process.waitUntilExit()
            let output = try standardOutput.fileHandleForReading.readToEnd() ?? Data()
            _ = try standardError.fileHandleForReading.readToEnd()
            XCTAssertEqual(process.terminationReason, .exit)
            XCTAssertEqual(process.terminationStatus, 0)
            let raw = try JSONSerialization.jsonObject(with: output)
            guard let observation = raw as? [String: [String: String]] else {
                XCTFail("the environment observer did not return two dictionaries")
                return
            }
            XCTAssertEqual(observation.keys.sorted(), [
                "foundationEnvironment", "rawCEnvironment",
            ])
            XCTAssertEqual(observation["rawCEnvironment"], environment)
            XCTAssertEqual(observation["foundationEnvironment"], environment)
            observations.append(observation)
        }
        XCTAssertEqual(observations[0], observations[1])

        let digest = try SwanSongAuthorizedProcessEnvironmentContract
            .canonicalEnvironmentSHA256(environment)
        if environment["__CF_USER_TEXT_ENCODING"] == "0x1F5:0x0:0x0" {
            XCTAssertEqual(
                digest,
                "5115cca8bead847e36ef5ffe2930888680c2a74871e65e92cf8419eaed933b6f"
            )
        }
        for observed in observations[0].values {
            _ = try SwanSongAuthorizedProcessEnvironmentContract.validate(
                expectedEnvironment: environment,
                expectedEnvironmentSHA256: digest,
                canonicalEngineDirectory: "/engine",
                actualEnvironment: observed
            )
        }
    }
}
