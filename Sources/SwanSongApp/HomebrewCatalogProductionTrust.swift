import Foundation
import SwanSongKit

/// Production catalog trust contains only the purpose-specific public key from
/// RegionallyFamous/swansong-catalog. The signing key is never shipped here.
enum HomebrewCatalogProductionTrust {
    enum PublicationStatus {
        case comingSoon
        case published
    }

    /// This explicit release state is checked together with the trust table
    /// and public catalog before an official app can be built. Changing it to
    /// `.published` without a reachable, validly signed catalog fails the
    /// release-readiness gate.
    static let publicationStatus: PublicationStatus = .published
    static let minimumRevision = 1

    static let trustedKeys: [HomebrewCatalogTrustedKey] = [
        HomebrewCatalogTrustedKey(
            keyID: "ed25519-68d24903f9a749d7",
            rawPublicKey: Data(
                base64Encoded: "+AeyqHDUdhMqtjYADGDJrVfxQBz0LWfxYi3/cvJZfSY="
            )!,
            minimumRevision: 1
        ),
    ]

    static let verifier = HomebrewCatalogSignatureVerifier(
        trustedKeys: trustedKeys,
        contract: .rawEd25519(
            keyID: "ed25519-68d24903f9a749d7",
            expectedCatalogSHA256: nil
        )
    )
}
