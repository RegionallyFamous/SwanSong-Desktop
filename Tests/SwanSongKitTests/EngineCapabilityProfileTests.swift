import Foundation
@testable import SwanSongKit
import XCTest

final class EngineCapabilityProfileTests: XCTestCase {
    func testConsumedPrefetchProfileRequiresExactABI10SuffixAndCapabilityBit() throws {
        let capabilities = EngineCapabilities(rawValue:
            EngineCapabilities.execution.rawValue
                | EngineCapabilities.consumedPrefetchProvenance.rawValue
        )
        let buildID = "ares-0123456789abcdef0123456789abcdef01234567-swan-abi10"

        let profile = try XCTUnwrap(
            EngineConsumedPrefetchCapabilityProfile.exact(
                engineABI: 10,
                engineBuildID: buildID,
                capabilities: capabilities
            )
        )
        XCTAssertEqual(profile.schema,
                       EngineConsumedPrefetchCapabilityProfile.currentSchema)
        XCTAssertEqual(profile.engineABI, 10)
        XCTAssertEqual(profile.engineBuildID, buildID)
        XCTAssertEqual(profile.engineCapabilitiesRaw, capabilities.rawValue)
        XCTAssertEqual(profile.requiredEngineABI, 10)
        XCTAssertEqual(profile.requiredBuildIDSuffix, "-swan-abi10")
        XCTAssertEqual(profile.capabilityBitRaw, UInt64(1) << 13)
        XCTAssertEqual(profile.sourceProbeProfile,
                       "diagnostic-future-source-probe-v5")

        XCTAssertNil(EngineConsumedPrefetchCapabilityProfile.exact(
            engineABI: 9,
            engineBuildID: buildID,
            capabilities: capabilities
        ))
        XCTAssertNil(EngineConsumedPrefetchCapabilityProfile.exact(
            engineABI: 10,
            engineBuildID: buildID.replacingOccurrences(of: "abi10", with: "abi9"),
            capabilities: capabilities
        ))
        XCTAssertNil(EngineConsumedPrefetchCapabilityProfile.exact(
            engineABI: 10,
            engineBuildID: buildID,
            capabilities: .execution
        ))
    }

    func testLiveRunnerBindsSourceProbeV4ToExactABI10Profile() throws {
        let result = try runRouteRunner([
            "engine-capability", "--enable-debug-tools",
        ])
        XCTAssertEqual(result.status, 0, result.output)
        let report = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.output.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(report["schema"] as? String,
                       "swan-song-route-runner-engine-capability-v2")
        XCTAssertEqual((report["engineABI"] as? NSNumber)?.uint32Value, 10)
        let buildID = try XCTUnwrap(report["engineBuildID"] as? String)
        XCTAssertTrue(buildID.hasSuffix("-swan-abi10"))
        let raw = try XCTUnwrap(
            (report["engineCapabilitiesRaw"] as? NSNumber)?.uint64Value
        )
        XCTAssertNotEqual(raw & (UInt64(1) << 13), 0)

        let profile = try XCTUnwrap(
            report["consumedPrefetchProvenance"] as? [String: Any]
        )
        XCTAssertEqual(Set(profile.keys), Set([
            "capabilityBitRaw", "engineABI", "engineBuildID",
            "engineCapabilitiesRaw", "requiredBuildIDSuffix",
            "requiredEngineABI", "schema", "sourceProbeProfile",
        ]))
        XCTAssertEqual(profile["engineBuildID"] as? String, buildID)
        XCTAssertEqual((profile["engineCapabilitiesRaw"] as? NSNumber)?.uint64Value,
                       raw)
        XCTAssertEqual((profile["capabilityBitRaw"] as? NSNumber)?.uint64Value,
                       UInt64(1) << 13)
        XCTAssertEqual(profile["sourceProbeProfile"] as? String,
                       "diagnostic-future-source-probe-v5")

        let sourceProbe = try XCTUnwrap(
            report["probeRectangleSource"] as? [String: Any]
        )
        XCTAssertEqual(sourceProbe["command"] as? String,
                       "probe-rectangle-source")
        XCTAssertEqual(sourceProbe["reportSchema"] as? String,
                       "swan-song-display-source-probe-report-v4")
        XCTAssertEqual(sourceProbe["privateDetailsSchema"] as? String,
                       "swan-song-display-source-probe-v4")
        XCTAssertEqual(sourceProbe["blockedReportSchema"] as? String,
                       "swan-song-display-source-probe-blocked-leaf-v2")
        XCTAssertEqual((sourceProbe["requiresEngineABI"] as? NSNumber)?.uint32Value,
                       10)
        XCTAssertEqual((sourceProbe["requiresEngineABI"] as? NSNumber)?.uint32Value,
                       (profile["engineABI"] as? NSNumber)?.uint32Value)
        XCTAssertEqual(sourceProbe["requiredEngineCapabilities"] as? [String], [
            "displayProvenance",
            "displaySourceProvenance",
            "displaySourceComponentSelection",
            "executedSourceReadContext",
            "displaySpriteAttributeProvenance",
        ])
        XCTAssertFalse(
            (sourceProbe["requiredEngineCapabilities"] as? [String] ?? [])
                .contains("consumedPrefetchProvenance")
        )
    }

    private func runRouteRunner(
        _ arguments: [String]
    ) throws -> (status: Int32, output: String) {
        var search = try XCTUnwrap(
            Bundle(for: EngineCapabilityProfileTests.self).executableURL
        )
        var runner: URL?
        for _ in 0..<8 {
            search.deleteLastPathComponent()
            let candidate = search.appendingPathComponent(
                "SwanSongRouteRunner",
                isDirectory: false
            )
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                runner = candidate
                break
            }
        }
        let process = Process()
        process.executableURL = try XCTUnwrap(runner)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        return (process.terminationStatus, output)
    }
}
