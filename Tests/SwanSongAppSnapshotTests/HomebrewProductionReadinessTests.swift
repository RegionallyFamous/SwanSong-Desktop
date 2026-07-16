import CryptoKit
import Foundation
import SwanSongKit
@testable import SwanSongApp
import XCTest

final class HomebrewProductionReadinessTests: XCTestCase {
    private static let enforcementEnvironmentKey =
        "SWAN_ENFORCE_HOMEBREW_PRODUCTION_READINESS"
    private static let repositoryEnvironmentKey = "SWAN_HOMEBREW_REPOSITORY_ROOT"

    func testProductionPublicationStateIsInternallyCoherent() {
        switch HomebrewCatalogProductionTrust.publicationStatus {
        case .comingSoon:
            XCTAssertTrue(
                HomebrewCatalogProductionTrust.trustedKeys.isEmpty,
                "Coming Soon must remain fail-closed with no production trust key."
            )
        case .published:
            XCTAssertFalse(
                HomebrewCatalogProductionTrust.trustedKeys.isEmpty,
                "A published catalog requires at least one production trust key."
            )
        }
    }

    @MainActor
    func testComingSoonLegalSupportCopyDoesNotAdvertiseAnActiveCatalog() {
        guard case .comingSoon = HomebrewCatalogProductionTrust.publicationStatus else {
            return
        }

        let view = LegalSupportView()
        let copy = [
            view.catalogOverviewText,
            view.catalogUpdatesDetail,
            view.catalogNetworkDetail,
        ].joined(separator: "\n").lowercased()

        for requiredPhrase in [
            "coming soon",
            "no network requests in this release",
            "unavailable homebrew catalog cannot contact github",
        ] {
            XCTAssertTrue(
                copy.contains(requiredPhrase),
                "Coming Soon legal/support copy must say: \(requiredPhrase)"
            )
        }
        for activeCatalogClaim in [
            "choose load catalog",
            "after catalog consent",
            "request a missing verified copy",
            "refreshing it",
            "when you refresh",
            "downloading a listed title",
            "when you download",
            "contacts github",
            "consented github requests",
        ] {
            XCTAssertFalse(
                copy.contains(activeCatalogClaim),
                "Coming Soon legal/support copy advertises active catalog behavior: \(activeCatalogClaim)"
            )
        }
    }

    func testEnforcedReleaseStateMatchesDocumentationAndPublishedCatalog() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment[Self.enforcementEnvironmentKey] == "1" else { return }
        let repositoryRoot = try XCTUnwrap(
            environment[Self.repositoryEnvironmentKey],
            "The release gate must provide the repository root."
        )

        let expectedDocumentationStatus: String
        switch HomebrewCatalogProductionTrust.publicationStatus {
        case .comingSoon:
            expectedDocumentationStatus = "coming-soon"
        case .published:
            expectedDocumentationStatus = "published"
        }
        for relativePath in ["README.md", "PRIVACY.md", "SUPPORT.md"] {
            let contents = try String(
                contentsOfFile: URL(fileURLWithPath: repositoryRoot)
                    .appendingPathComponent(relativePath).path,
                encoding: .utf8
            )
            XCTAssertTrue(
                contents.contains(
                    "<!-- homebrew-catalog-status: \(expectedDocumentationStatus) -->"
                ),
                "\(relativePath) does not match the production publication state."
            )
        }

        switch HomebrewCatalogProductionTrust.publicationStatus {
        case .comingSoon:
            XCTAssertTrue(HomebrewCatalogProductionTrust.trustedKeys.isEmpty)
            return
        case .published:
            break
        }

        let trustedKeys = HomebrewCatalogProductionTrust.trustedKeys
        XCTAssertFalse(trustedKeys.isEmpty)
        for key in trustedKeys {
            let digestPrefix = SHA256.hash(data: key.rawPublicKey)
                .prefix(8)
                .map { String(format: "%02x", $0) }
                .joined()
            XCTAssertEqual(
                key.keyID,
                "ed25519-\(digestPrefix)",
                "Production key IDs must be derived from the public key bytes."
            )
        }

        let client = HomebrewCatalogClient()
        let wireBundle = try await client.fetchCatalogBundle()
        let authenticated = try HomebrewCatalogProductionTrust.verifier.verify(
            catalogData: wireBundle.catalogData,
            signatureData: wireBundle.signatureData
        )
        let catalog = try HomebrewCatalogValidator.decode(
            wireBundle.catalogData,
            sourceURL: client.catalogSourceURL
        )
        XCTAssertFalse(
            catalog.entries.isEmpty,
            "A release must not advertise a published catalog with no installable titles."
        )
        _ = try HomebrewCatalogRollbackPolicy.nextState(
            catalog: catalog,
            authenticated: authenticated,
            trustedKeys: trustedKeys,
            minimumRevision: HomebrewCatalogProductionTrust.minimumRevision,
            currentState: nil
        )
    }
}
