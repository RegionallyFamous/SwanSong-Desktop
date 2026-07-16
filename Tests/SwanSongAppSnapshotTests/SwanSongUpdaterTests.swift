import Foundation
@testable import SwanSongApp
import XCTest

final class SwanSongUpdaterTests: XCTestCase {
    func testProductionConfigurationRequiresExactGitHubHostedFeedAndEd25519Key() throws {
        let publicKey = Data(repeating: 0x5A, count: 32).base64EncodedString()
        let configuration = try AppUpdateConfiguration(
            infoDictionary: updaterInfo(publicKey: publicKey)
        )

        XCTAssertEqual(configuration.feedURL, AppUpdateConfiguration.expectedFeedURL)
        XCTAssertEqual(configuration.publicKey, publicKey)
        XCTAssertEqual(configuration.feedURL.scheme, "https")
        XCTAssertEqual(configuration.feedURL.host, "raw.githubusercontent.com")
    }

    func testConfigurationFailsClosedWithoutSigningKey() {
        XCTAssertThrowsError(
            try AppUpdateConfiguration(
                infoDictionary: updaterInfo(publicKey: nil)
            )
        ) { error in
            XCTAssertEqual(error as? AppUpdateConfigurationError, .missingPublicKey)
        }
    }

    func testConfigurationRejectsAlternateFeedAndMalformedSigningKey() {
        let publicKey = Data(repeating: 0xA5, count: 32).base64EncodedString()

        XCTAssertThrowsError(
            try AppUpdateConfiguration(
                infoDictionary: updaterInfo(
                    feedURL: "https://example.com/appcast.xml",
                    publicKey: publicKey
                )
            )
        ) { error in
            XCTAssertEqual(error as? AppUpdateConfigurationError, .untrustedFeedURL)
        }

        XCTAssertThrowsError(
            try AppUpdateConfiguration(
                infoDictionary: updaterInfo(publicKey: "not-a-key")
            )
        ) { error in
            XCTAssertEqual(error as? AppUpdateConfigurationError, .invalidPublicKey)
        }
    }

    func testConfigurationFailsClosedWhenPrivacyOrSignaturePolicyDrifts() {
        let publicKey = Data(repeating: 0x3C, count: 32).base64EncodedString()
        var info = updaterInfo(publicKey: publicKey)
        info["SUEnableSystemProfiling"] = true

        XCTAssertThrowsError(try AppUpdateConfiguration(infoDictionary: info)) { error in
            XCTAssertEqual(error as? AppUpdateConfigurationError, .unsafeUpdaterPolicy)
        }

        info = updaterInfo(publicKey: publicKey)
        info["SUSendProfileInfo"] = true
        XCTAssertThrowsError(try AppUpdateConfiguration(infoDictionary: info)) { error in
            XCTAssertEqual(error as? AppUpdateConfigurationError, .unsafeUpdaterPolicy)
        }
    }

    func testBetaChannelIsExplicitOptIn() {
        XCTAssertEqual(
            AppUpdateChannelPolicy.allowedChannels(includeBeta: false),
            []
        )
        XCTAssertEqual(
            AppUpdateChannelPolicy.allowedChannels(includeBeta: true),
            [AppUpdateChannelPolicy.betaChannel]
        )
        XCTAssertFalse(
            AppUpdateNetworkPolicy.shouldResetUpdateCycle(
                automaticallyChecksForUpdates: false
            )
        )
        XCTAssertTrue(
            AppUpdateNetworkPolicy.shouldResetUpdateCycle(
                automaticallyChecksForUpdates: true
            )
        )
    }

    func testSystemProfileAllowlistIsAlwaysEmpty() {
        XCTAssertEqual(AppUpdateNetworkPolicy.allowedSystemProfileKeys, [])
    }

    private func updaterInfo(
        feedURL: String = AppUpdateConfiguration.expectedFeedURL.absoluteString,
        publicKey: String?
    ) -> [String: Any] {
        var info: [String: Any] = [AppUpdateConfiguration.feedURLKey: feedURL]
        if let publicKey {
            info[AppUpdateConfiguration.publicKeyKey] = publicKey
        }
        for (key, value) in AppUpdateConfiguration.requiredBooleanPolicies {
            info[key] = value
        }
        return info
    }
}
