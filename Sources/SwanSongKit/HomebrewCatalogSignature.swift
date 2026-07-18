import CryptoKit
import Foundation

public struct HomebrewCatalogDetachedSignature: Codable, Equatable, Sendable {
    public let keyID: String
    public let signature: String

    public init(keyID: String, signature: String) {
        self.keyID = keyID
        self.signature = signature
    }
}

public struct HomebrewCatalogSignatureEnvelope: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let algorithm = "Ed25519"
    public static let maximumByteCount = 8 * 1_024
    public static let maximumSignatureCount = 4

    public let schemaVersion: Int
    public let algorithm: String
    public let catalogSHA256: String
    public let catalogByteCount: Int
    public let signatures: [HomebrewCatalogDetachedSignature]

    public init(
        catalogSHA256: String,
        catalogByteCount: Int,
        signatures: [HomebrewCatalogDetachedSignature]
    ) {
        self.schemaVersion = Self.schemaVersion
        self.algorithm = Self.algorithm
        self.catalogSHA256 = catalogSHA256
        self.catalogByteCount = catalogByteCount
        self.signatures = signatures
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumByteCount else {
            throw HomebrewCatalogSignatureError.invalidEnvelope
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HomebrewCatalogSignatureError.invalidEnvelope
        }
        guard let root = object as? [String: Any],
              Set(root.keys) == [
                  "schemaVersion", "algorithm", "catalogSHA256",
                  "catalogByteCount", "signatures",
              ],
              let rawSignatures = root["signatures"] as? [Any],
              rawSignatures.allSatisfy({ value in
                  guard let signature = value as? [String: Any] else { return false }
                  return Set(signature.keys) == ["keyID", "signature"]
              }) else {
            throw HomebrewCatalogSignatureError.invalidEnvelope
        }
        let envelope: Self
        do {
            envelope = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw HomebrewCatalogSignatureError.invalidEnvelope
        }
        guard envelope.schemaVersion == schemaVersion else {
            throw HomebrewCatalogSignatureError.unsupportedSchemaVersion(
                envelope.schemaVersion
            )
        }
        guard envelope.algorithm == algorithm else {
            throw HomebrewCatalogSignatureError.unsupportedAlgorithm(
                envelope.algorithm
            )
        }
        guard envelope.catalogByteCount > 0,
              envelope.catalogByteCount <= HomebrewCatalogValidator.maximumCatalogByteCount,
              Self.isLowercaseSHA256(envelope.catalogSHA256),
              !envelope.signatures.isEmpty,
              envelope.signatures.count <= maximumSignatureCount else {
            throw HomebrewCatalogSignatureError.invalidEnvelope
        }

        var keyIDs = Set<String>()
        for signature in envelope.signatures {
            guard Self.isKeyID(signature.keyID),
                  keyIDs.insert(signature.keyID).inserted,
                  let bytes = Self.canonicalBase64(signature.signature),
                  bytes.count == 64 else {
                throw HomebrewCatalogSignatureError.invalidEnvelope
            }
        }
        return envelope
    }

    static func canonicalBase64(_ value: String) -> Data? {
        guard let data = Data(base64Encoded: value),
              data.base64EncodedString() == value else { return nil }
        return data
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    private static func isKeyID(_ value: String) -> Bool {
        let bytes = value.utf8
        return bytes.count >= 8 && bytes.count <= 80 && bytes.allSatisfy {
            ($0 >= 48 && $0 <= 57)
                || ($0 >= 65 && $0 <= 90)
                || ($0 >= 97 && $0 <= 122)
                || $0 == 45
                || $0 == 46
                || $0 == 95
        }
    }
}

public struct HomebrewCatalogTrustedKey: Equatable, Sendable {
    public let keyID: String
    public let rawPublicKey: Data
    public let minimumRevision: Int
    public let maximumRevision: Int?

    public init(
        keyID: String,
        rawPublicKey: Data,
        minimumRevision: Int = 1,
        maximumRevision: Int? = nil
    ) {
        self.keyID = keyID
        self.rawPublicKey = rawPublicKey
        self.minimumRevision = minimumRevision
        self.maximumRevision = maximumRevision
    }

    public func accepts(revision: Int) -> Bool {
        revision >= minimumRevision
            && maximumRevision.map { revision <= $0 } != false
    }
}

public enum HomebrewCatalogSignatureContract: Equatable, Sendable {
    /// SwanSong's original rotation-capable JSON signature envelope.
    case envelope
    /// One canonical base64 Ed25519 signature over the exact catalog bytes.
    /// The optional digest binds an app release to an immutable publication.
    case rawEd25519(keyID: String, expectedCatalogSHA256: String?)
}

public struct AuthenticatedHomebrewCatalog: Equatable, Sendable {
    public let catalogData: Data
    public let signatureData: Data
    public let catalogSHA256: String
    public let cryptographicallyValidKeyIDs: Set<String>

    init(
        catalogData: Data,
        signatureData: Data,
        catalogSHA256: String,
        cryptographicallyValidKeyIDs: Set<String>
    ) {
        self.catalogData = catalogData
        self.signatureData = signatureData
        self.catalogSHA256 = catalogSHA256
        self.cryptographicallyValidKeyIDs = cryptographicallyValidKeyIDs
    }

    public func acceptedKeyID(
        for revision: Int,
        trustedKeys: [HomebrewCatalogTrustedKey]
    ) -> String? {
        trustedKeys.first {
            cryptographicallyValidKeyIDs.contains($0.keyID)
                && $0.accepts(revision: revision)
        }?.keyID
    }
}

public struct HomebrewCatalogSignatureVerifier: Sendable {
    public let trustedKeys: [HomebrewCatalogTrustedKey]
    public let contract: HomebrewCatalogSignatureContract

    public init(
        trustedKeys: [HomebrewCatalogTrustedKey],
        contract: HomebrewCatalogSignatureContract = .envelope
    ) {
        self.trustedKeys = trustedKeys
        self.contract = contract
    }

    public func verify(
        catalogData: Data,
        signatureData: Data
    ) throws -> AuthenticatedHomebrewCatalog {
        guard !catalogData.isEmpty,
              catalogData.count <= HomebrewCatalogValidator.maximumCatalogByteCount else {
            throw HomebrewCatalogSignatureError.invalidCatalogBytes
        }
        switch contract {
        case .envelope:
            return try verifyEnvelope(
                catalogData: catalogData,
                signatureData: signatureData
            )
        case let .rawEd25519(keyID, expectedCatalogSHA256):
            return try verifyRawSignature(
                catalogData: catalogData,
                signatureData: signatureData,
                keyID: keyID,
                expectedCatalogSHA256: expectedCatalogSHA256
            )
        }
    }

    private func verifyEnvelope(
        catalogData: Data,
        signatureData: Data
    ) throws -> AuthenticatedHomebrewCatalog {
        let envelope = try HomebrewCatalogSignatureEnvelope.decode(signatureData)
        guard envelope.catalogByteCount == catalogData.count else {
            throw HomebrewCatalogSignatureError.catalogByteCountMismatch
        }
        let digest = Self.sha256(catalogData)
        guard envelope.catalogSHA256 == digest else {
            throw HomebrewCatalogSignatureError.catalogDigestMismatch
        }

        var trustedByID: [String: HomebrewCatalogTrustedKey] = [:]
        for key in trustedKeys {
            guard trustedByID[key.keyID] == nil,
                  key.minimumRevision >= 1,
                  key.maximumRevision.map({ $0 >= key.minimumRevision }) != false,
                  (try? Curve25519.Signing.PublicKey(
                      rawRepresentation: key.rawPublicKey
                  )) != nil else {
                throw HomebrewCatalogSignatureError.invalidTrustedKey(key.keyID)
            }
            trustedByID[key.keyID] = key
        }

        var validKeyIDs = Set<String>()
        for detached in envelope.signatures {
            guard let trusted = trustedByID[detached.keyID],
                  let signature = HomebrewCatalogSignatureEnvelope.canonicalBase64(
                      detached.signature
                  ),
                  let publicKey = try? Curve25519.Signing.PublicKey(
                      rawRepresentation: trusted.rawPublicKey
                  ),
                  publicKey.isValidSignature(signature, for: catalogData) else {
                continue
            }
            validKeyIDs.insert(detached.keyID)
        }
        guard !validKeyIDs.isEmpty else {
            throw trustedKeys.isEmpty
                ? HomebrewCatalogSignatureError.noProductionTrustAnchor
                : HomebrewCatalogSignatureError.noTrustedSignature
        }
        return AuthenticatedHomebrewCatalog(
            catalogData: catalogData,
            signatureData: signatureData,
            catalogSHA256: digest,
            cryptographicallyValidKeyIDs: validKeyIDs
        )
    }

    private func verifyRawSignature(
        catalogData: Data,
        signatureData: Data,
        keyID: String,
        expectedCatalogSHA256: String?
    ) throws -> AuthenticatedHomebrewCatalog {
        let digest = Self.sha256(catalogData)
        guard expectedCatalogSHA256.map({ $0 == digest }) != false else {
            throw HomebrewCatalogSignatureError.catalogDigestMismatch
        }
        guard signatureData.count <= HomebrewCatalogSignatureEnvelope.maximumByteCount,
              let text = String(data: signatureData, encoding: .utf8) else {
            throw HomebrewCatalogSignatureError.invalidEnvelope
        }
        let value: String
        if text.hasSuffix("\n") {
            value = String(text.dropLast())
            guard !value.hasSuffix("\r"), !value.contains("\n") else {
                throw HomebrewCatalogSignatureError.invalidEnvelope
            }
        } else {
            value = text
        }
        guard let signature = HomebrewCatalogSignatureEnvelope.canonicalBase64(value),
              signature.count == 64 else {
            throw HomebrewCatalogSignatureError.invalidEnvelope
        }
        let keys = try validatedTrustedKeys()
        guard let trusted = keys[keyID],
              let publicKey = try? Curve25519.Signing.PublicKey(
                  rawRepresentation: trusted.rawPublicKey
              ),
              publicKey.isValidSignature(signature, for: catalogData) else {
            throw trustedKeys.isEmpty
                ? HomebrewCatalogSignatureError.noProductionTrustAnchor
                : HomebrewCatalogSignatureError.noTrustedSignature
        }
        return AuthenticatedHomebrewCatalog(
            catalogData: catalogData,
            signatureData: signatureData,
            catalogSHA256: digest,
            cryptographicallyValidKeyIDs: [keyID]
        )
    }

    private func validatedTrustedKeys() throws -> [String: HomebrewCatalogTrustedKey] {
        var trustedByID: [String: HomebrewCatalogTrustedKey] = [:]
        for key in trustedKeys {
            guard trustedByID[key.keyID] == nil,
                  key.minimumRevision >= 1,
                  key.maximumRevision.map({ $0 >= key.minimumRevision }) != false,
                  (try? Curve25519.Signing.PublicKey(
                      rawRepresentation: key.rawPublicKey
                  )) != nil else {
                throw HomebrewCatalogSignatureError.invalidTrustedKey(key.keyID)
            }
            trustedByID[key.keyID] = key
        }
        return trustedByID
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum HomebrewCatalogSignatureError: LocalizedError, Equatable, Sendable {
    case invalidCatalogBytes
    case invalidEnvelope
    case unsupportedSchemaVersion(Int)
    case unsupportedAlgorithm(String)
    case catalogByteCountMismatch
    case catalogDigestMismatch
    case invalidTrustedKey(String)
    case noProductionTrustAnchor
    case noTrustedSignature
    case keyNotValidForRevision

    public var errorDescription: String? {
        switch self {
        case .invalidCatalogBytes:
            "The signed homebrew catalog is empty or exceeds SwanSong’s size limit."
        case .invalidEnvelope:
            "The detached homebrew catalog signature has an invalid v1 schema."
        case let .unsupportedSchemaVersion(version):
            "Detached homebrew catalog signature schema \(version) is not supported."
        case let .unsupportedAlgorithm(algorithm):
            "Detached homebrew catalog signature algorithm \(algorithm) is not supported."
        case .catalogByteCountMismatch:
            "The catalog and detached signature publish different byte counts."
        case .catalogDigestMismatch:
            "The catalog and detached signature publish different SHA-256 digests."
        case let .invalidTrustedKey(keyID):
            "The embedded homebrew catalog key \(keyID) is invalid."
        case .noProductionTrustAnchor:
            "This SwanSong build has no production homebrew catalog signing key yet."
        case .noTrustedSignature:
            "The homebrew catalog has no valid signature from a key trusted by this SwanSong build."
        case .keyNotValidForRevision:
            "The valid catalog signing key is not authorized for this catalog revision."
        }
    }
}

public struct HomebrewCatalogHighWaterState: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let catalogID: String
    public let highestRevision: Int
    public let catalogSHA256: String
    public let generatedAt: Date
    public let acceptedKeyID: String

    public init(
        catalogID: String,
        highestRevision: Int,
        catalogSHA256: String,
        generatedAt: Date,
        acceptedKeyID: String
    ) {
        self.schemaVersion = Self.schemaVersion
        self.catalogID = catalogID
        self.highestRevision = highestRevision
        self.catalogSHA256 = catalogSHA256
        self.generatedAt = generatedAt
        self.acceptedKeyID = acceptedKeyID
    }
}

public enum HomebrewCatalogRollbackPolicy {
    public static func nextState(
        catalog: HomebrewCatalog,
        authenticated: AuthenticatedHomebrewCatalog,
        trustedKeys: [HomebrewCatalogTrustedKey],
        minimumRevision: Int,
        currentState: HomebrewCatalogHighWaterState?
    ) throws -> HomebrewCatalogHighWaterState {
        guard catalog.revision >= minimumRevision else {
            throw HomebrewCatalogRollbackError.belowApplicationRevisionFloor
        }
        guard let acceptedKeyID = authenticated.acceptedKeyID(
            for: catalog.revision,
            trustedKeys: trustedKeys
        ) else {
            throw HomebrewCatalogSignatureError.keyNotValidForRevision
        }
        guard let currentState else {
            return HomebrewCatalogHighWaterState(
                catalogID: catalog.catalogID,
                highestRevision: catalog.revision,
                catalogSHA256: authenticated.catalogSHA256,
                generatedAt: catalog.generatedAt,
                acceptedKeyID: acceptedKeyID
            )
        }
        guard currentState.schemaVersion == HomebrewCatalogHighWaterState.schemaVersion,
              currentState.catalogID == catalog.catalogID,
              currentState.highestRevision >= 1 else {
            throw HomebrewCatalogRollbackError.invalidHighWaterState
        }
        guard catalog.revision >= currentState.highestRevision else {
            throw HomebrewCatalogRollbackError.revisionDowngrade
        }
        if catalog.revision == currentState.highestRevision {
            guard authenticated.catalogSHA256 == currentState.catalogSHA256 else {
                throw HomebrewCatalogRollbackError.mutableRevision
            }
            return currentState
        }
        guard catalog.generatedAt >= currentState.generatedAt else {
            throw HomebrewCatalogRollbackError.nonmonotonicRevisionDate
        }
        return HomebrewCatalogHighWaterState(
            catalogID: catalog.catalogID,
            highestRevision: catalog.revision,
            catalogSHA256: authenticated.catalogSHA256,
            generatedAt: catalog.generatedAt,
            acceptedKeyID: acceptedKeyID
        )
    }
}

public enum HomebrewCatalogRollbackError: LocalizedError, Equatable, Sendable {
    case belowApplicationRevisionFloor
    case revisionDowngrade
    case mutableRevision
    case nonmonotonicRevisionDate
    case invalidHighWaterState

    public var errorDescription: String? {
        switch self {
        case .belowApplicationRevisionFloor:
            "The catalog predates the oldest revision accepted by this SwanSong build."
        case .revisionDowngrade:
            "The catalog revision is older than the highest revision already verified on this Mac."
        case .mutableRevision:
            "The catalog changed its exact bytes without increasing its revision."
        case .nonmonotonicRevisionDate:
            "The catalog revision increased while its generation date moved backward."
        case .invalidHighWaterState:
            "The saved catalog anti-rollback state is invalid."
        }
    }
}
