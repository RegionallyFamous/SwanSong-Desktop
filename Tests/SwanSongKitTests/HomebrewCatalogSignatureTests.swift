import CryptoKit
import Foundation
@testable import SwanSongKit
import XCTest

final class HomebrewCatalogSignatureTests: XCTestCase {
    private let keyID = "ed25519-test-9d61b19deffd5a60"

    func testVerifiesSignatureOverExactCatalogBytes() throws {
        let catalogData = Data(#"{"schemaVersion":1,"revision":1}"#.utf8)
        let fixture = try signedFixture(catalogData)

        let authenticated = try fixture.verifier.verify(
            catalogData: catalogData,
            signatureData: fixture.signatureData
        )

        XCTAssertEqual(authenticated.catalogData, catalogData)
        XCTAssertEqual(
            authenticated.catalogSHA256,
            HomebrewCatalogSignatureVerifier.sha256(catalogData)
        )
        XCTAssertEqual(authenticated.cryptographicallyValidKeyIDs, [keyID])
    }

    func testWhitespaceOrSignatureMutationFailsClosed() throws {
        let catalogData = Data(#"{"revision":1}"#.utf8)
        let fixture = try signedFixture(catalogData)
        var changedCatalog = catalogData
        changedCatalog.append(0x0a)

        XCTAssertThrowsError(
            try fixture.verifier.verify(
                catalogData: changedCatalog,
                signatureData: fixture.signatureData
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogSignatureError,
                .catalogByteCountMismatch
            )
        }

        var envelope = try HomebrewCatalogSignatureEnvelope.decode(
            fixture.signatureData
        )
        var signature = try XCTUnwrap(
            Data(base64Encoded: envelope.signatures[0].signature)
        )
        signature[0] ^= 0xff
        envelope = HomebrewCatalogSignatureEnvelope(
            catalogSHA256: envelope.catalogSHA256,
            catalogByteCount: envelope.catalogByteCount,
            signatures: [
                HomebrewCatalogDetachedSignature(
                    keyID: keyID,
                    signature: signature.base64EncodedString()
                ),
            ]
        )
        XCTAssertThrowsError(
            try fixture.verifier.verify(
                catalogData: catalogData,
                signatureData: envelope.encoded()
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogSignatureError,
                .noTrustedSignature
            )
        }
    }

    func testEnvelopeRejectsUnknownKeysDuplicateIDsAndNoncanonicalBase64() throws {
        let unknown = Data(
            #"{"algorithm":"Ed25519","catalogByteCount":2,"catalogSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schemaVersion":1,"signatures":[{"keyID":"test-key","signature":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="}],"extra":true}"#.utf8
        )
        assertInvalidEnvelope(unknown)

        let signature = Data(repeating: 0, count: 64).base64EncodedString()
        let duplicate = HomebrewCatalogSignatureEnvelope(
            catalogSHA256: String(repeating: "a", count: 64),
            catalogByteCount: 2,
            signatures: [
                .init(keyID: "duplicate-key", signature: signature),
                .init(keyID: "duplicate-key", signature: signature),
            ]
        )
        assertInvalidEnvelope(try duplicate.encoded())

        let noncanonical = Data(
            #"{"algorithm":"Ed25519","catalogByteCount":2,"catalogSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schemaVersion":1,"signatures":[{"keyID":"test-key","signature":" AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="}]}"#.utf8
        )
        assertInvalidEnvelope(noncanonical)
    }

    func testDualSignatureRotationAcceptsRecognizedValidKey() throws {
        let catalogData = Data("rotation".utf8)
        let trustedPrivate = try deterministicPrivateKey()
        let futurePrivate = Curve25519.Signing.PrivateKey()
        let signatures = [
            HomebrewCatalogDetachedSignature(
                keyID: "future-key",
                signature: try futurePrivate.signature(for: catalogData)
                    .base64EncodedString()
            ),
            HomebrewCatalogDetachedSignature(
                keyID: keyID,
                signature: try trustedPrivate.signature(for: catalogData)
                    .base64EncodedString()
            ),
        ]
        let envelope = HomebrewCatalogSignatureEnvelope(
            catalogSHA256: HomebrewCatalogSignatureVerifier.sha256(catalogData),
            catalogByteCount: catalogData.count,
            signatures: signatures
        )
        let verifier = HomebrewCatalogSignatureVerifier(
            trustedKeys: [
                .init(
                    keyID: keyID,
                    rawPublicKey: trustedPrivate.publicKey.rawRepresentation
                ),
            ]
        )

        let authenticated = try verifier.verify(
            catalogData: catalogData,
            signatureData: envelope.encoded()
        )
        XCTAssertEqual(authenticated.cryptographicallyValidKeyIDs, [keyID])
    }

    func testNoProductionTrustAnchorIsExplicitlyFailClosed() throws {
        let catalogData = Data("catalog".utf8)
        let fixture = try signedFixture(catalogData)
        let verifier = HomebrewCatalogSignatureVerifier(trustedKeys: [])

        XCTAssertThrowsError(
            try verifier.verify(
                catalogData: catalogData,
                signatureData: fixture.signatureData
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogSignatureError,
                .noProductionTrustAnchor
            )
        }
    }

    func testRawDetachedSignatureContractAcceptsOnlyExactCanonicalBytes() throws {
        let catalogData = Data("published-catalog".utf8)
        let privateKey = try deterministicPrivateKey()
        let signature = try privateKey.signature(for: catalogData)
            .base64EncodedString()
        let verifier = HomebrewCatalogSignatureVerifier(
            trustedKeys: [
                .init(
                    keyID: keyID,
                    rawPublicKey: privateKey.publicKey.rawRepresentation
                ),
            ],
            contract: .rawEd25519(keyID: keyID, expectedCatalogSHA256: nil)
        )

        let authenticated = try verifier.verify(
            catalogData: catalogData,
            signatureData: Data((signature + "\n").utf8)
        )
        XCTAssertEqual(authenticated.cryptographicallyValidKeyIDs, [keyID])

        XCTAssertThrowsError(
            try verifier.verify(
                catalogData: catalogData + Data([0x0a]),
                signatureData: Data((signature + "\n").utf8)
            )
        ) { error in
            XCTAssertEqual(error as? HomebrewCatalogSignatureError, .noTrustedSignature)
        }
    }

    func testRollbackPolicyPersistsRevisionDigestAndKeyWindow() throws {
        let catalogData = Data("revision-one".utf8)
        let fixture = try signedFixture(catalogData, minimumRevision: 1, maximumRevision: 2)
        let authenticated = try fixture.verifier.verify(
            catalogData: catalogData,
            signatureData: fixture.signatureData
        )
        let catalog = makeCatalog(revision: 1, generatedAt: 1_750_000_000)
        let state = try HomebrewCatalogRollbackPolicy.nextState(
            catalog: catalog,
            authenticated: authenticated,
            trustedKeys: fixture.verifier.trustedKeys,
            minimumRevision: 1,
            currentState: nil
        )
        XCTAssertEqual(state.highestRevision, 1)
        XCTAssertEqual(state.catalogSHA256, authenticated.catalogSHA256)

        XCTAssertThrowsError(
            try HomebrewCatalogRollbackPolicy.nextState(
                catalog: catalog,
                authenticated: try signedFixture(Data("changed".utf8)).verifier.verify(
                    catalogData: Data("changed".utf8),
                    signatureData: signedFixture(Data("changed".utf8)).signatureData
                ),
                trustedKeys: fixture.verifier.trustedKeys,
                minimumRevision: 1,
                currentState: state
            )
        )

        let revisionThreeData = Data("revision-three".utf8)
        let revisionThreeFixture = try signedFixture(
            revisionThreeData,
            minimumRevision: 1,
            maximumRevision: 2
        )
        let revisionThreeAuth = try revisionThreeFixture.verifier.verify(
            catalogData: revisionThreeData,
            signatureData: revisionThreeFixture.signatureData
        )
        XCTAssertThrowsError(
            try HomebrewCatalogRollbackPolicy.nextState(
                catalog: makeCatalog(revision: 3, generatedAt: 1_750_000_100),
                authenticated: revisionThreeAuth,
                trustedKeys: revisionThreeFixture.verifier.trustedKeys,
                minimumRevision: 1,
                currentState: state
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogSignatureError,
                .keyNotValidForRevision
            )
        }
    }

    private func signedFixture(
        _ catalogData: Data,
        minimumRevision: Int = 1,
        maximumRevision: Int? = nil
    ) throws -> (signatureData: Data, verifier: HomebrewCatalogSignatureVerifier) {
        let privateKey = try deterministicPrivateKey()
        let signature = try privateKey.signature(for: catalogData)
        let envelope = HomebrewCatalogSignatureEnvelope(
            catalogSHA256: HomebrewCatalogSignatureVerifier.sha256(catalogData),
            catalogByteCount: catalogData.count,
            signatures: [
                .init(keyID: keyID, signature: signature.base64EncodedString()),
            ]
        )
        let verifier = HomebrewCatalogSignatureVerifier(
            trustedKeys: [
                .init(
                    keyID: keyID,
                    rawPublicKey: privateKey.publicKey.rawRepresentation,
                    minimumRevision: minimumRevision,
                    maximumRevision: maximumRevision
                ),
            ]
        )
        return (try envelope.encoded(), verifier)
    }

    private func deterministicPrivateKey() throws -> Curve25519.Signing.PrivateKey {
        try Curve25519.Signing.PrivateKey(
            rawRepresentation: Data(hex: "9d61b19deffd5a60ba844af492ec2cc4" +
                "4449c5697b326919703bac031cae7f60")
        )
    }

    private func makeCatalog(revision: Int, generatedAt: TimeInterval) -> HomebrewCatalog {
        HomebrewCatalog(
            catalogID: HomebrewCatalogValidator.firstPartyCatalogID,
            revision: revision,
            generatedAt: Date(timeIntervalSince1970: generatedAt),
            repositoryURL: HomebrewCatalogValidator.firstPartyRepositoryURL,
            entries: []
        )
    }

    private func assertInvalidEnvelope(_ data: Data) {
        XCTAssertThrowsError(try HomebrewCatalogSignatureEnvelope.decode(data)) { error in
            XCTAssertEqual(error as? HomebrewCatalogSignatureError, .invalidEnvelope)
        }
    }
}
private extension Data {
    init(hex: String) {
        self.init()
        reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
    }
}
