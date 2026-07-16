import Foundation
import SwanSongKit

/// Production catalog trust is intentionally fail-closed until the one-time
/// offline signing ceremony supplies the first public key. Never place a test
/// key or a private key in this table.
enum HomebrewCatalogProductionTrust {
    enum PublicationStatus {
        case comingSoon
        case published
    }

    /// This explicit release state is checked together with the trust table
    /// and public catalog before an official app can be built. Changing it to
    /// `.published` without a reachable, validly signed catalog fails the
    /// release-readiness gate.
    static let publicationStatus: PublicationStatus = .comingSoon
    static let minimumRevision = 1

    static let trustedKeys: [HomebrewCatalogTrustedKey] = [
        // Pending production key:
        // HomebrewCatalogTrustedKey(
        //     keyID: "ed25519-<first-16-hex-of-public-key-sha256>",
        //     rawPublicKey: Data(base64Encoded: "<32-byte-public-key>")!,
        //     minimumRevision: 1
        // ),
    ]

    static let verifier = HomebrewCatalogSignatureVerifier(
        trustedKeys: trustedKeys
    )
}
