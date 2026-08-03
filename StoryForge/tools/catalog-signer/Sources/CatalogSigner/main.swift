import CryptoKit
import Darwin
import Foundation

private let maximumCatalogBytes = 1 * 1_024 * 1_024
private let maximumEnvelopeBytes = 8 * 1_024
private let maximumSignatures = 4

private struct DetachedSignature: Codable {
    let keyID: String
    let signature: String
}

private struct SignatureEnvelope: Codable {
    let schemaVersion: Int
    let algorithm: String
    let catalogSHA256: String
    let catalogByteCount: Int
    let signatures: [DetachedSignature]
}

private struct PublicKeyDocument: Codable {
    let schemaVersion: Int
    let algorithm: String
    let keyID: String
    let publicKey: String
}

private struct Arguments {
    let command: String
    let options: [String: [String]]

    init(_ raw: [String]) throws {
        guard let command = raw.first else { throw ToolError.usage }
        self.command = command
        var parsed: [String: [String]] = [:]
        var index = 1
        while index < raw.count {
            let name = raw[index]
            guard name.hasPrefix("--"), index + 1 < raw.count else {
                throw ToolError.usage
            }
            parsed[name, default: []].append(raw[index + 1])
            index += 2
        }
        self.options = parsed
    }

    func one(_ name: String) throws -> String {
        guard let values = options[name], values.count == 1 else {
            throw ToolError.missingOption(name)
        }
        return values[0]
    }

    func many(_ name: String) throws -> [String] {
        guard let values = options[name], !values.isEmpty else {
            throw ToolError.missingOption(name)
        }
        return values
    }

    func rejectUnknown(_ allowed: Set<String>) throws {
        let unknown = Set(options.keys).subtracting(allowed)
        guard unknown.isEmpty else {
            throw ToolError.unknownOption(unknown.sorted().joined(separator: ", "))
        }
    }
}

private enum ToolError: LocalizedError {
    case usage
    case missingOption(String)
    case unknownOption(String)
    case unsafePrivateKey(String)
    case invalidKey(String)
    case keyIDMismatch(expected: String, actual: String)
    case invalidCatalog
    case invalidEnvelope
    case noTrustedSignature
    case outputExists(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            Self.usageText
        case let .missingOption(option):
            "Missing or repeated required option: \(option)"
        case let .unknownOption(option):
            "Unknown option: \(option)"
        case let .unsafePrivateKey(reason):
            "Refusing unsafe private-key file: \(reason)"
        case let .invalidKey(path):
            "Invalid Ed25519 key: \(path)"
        case let .keyIDMismatch(expected, actual):
            "Signing key ID mismatch: expected \(expected), received \(actual)"
        case .invalidCatalog:
            "Catalog must contain 1 byte through 1 MiB."
        case .invalidEnvelope:
            "Detached signature envelope is invalid."
        case .noTrustedSignature:
            "No detached signature verifies with the supplied public keys."
        case let .outputExists(path):
            "Refusing to replace private key output: \(path)"
        }
    }

    static let usageText = """
    Usage:
      catalog-signer generate-key --private-key PATH --public-key PATH
      catalog-signer export-public --private-key PATH --public-key PATH
      catalog-signer sign --catalog PATH --output PATH --signing-key KEY_ID=PRIVATE_KEY_PATH [--signing-key ...]
      catalog-signer verify --catalog PATH --signature PATH --public-key PATH [--public-key ...]
    """
}

@main
private enum CatalogSignerMain {
    static func main() {
        do {
            let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
            switch arguments.command {
            case "generate-key":
                try generateKey(arguments)
            case "export-public":
                try exportPublic(arguments)
            case "sign":
                try sign(arguments)
            case "verify":
                try verify(arguments)
            default:
                throw ToolError.usage
            }
        } catch {
            FileHandle.standardError.write(
                Data("catalog-signer: \(error.localizedDescription)\n".utf8)
            )
            exit(2)
        }
    }

    private static func generateKey(_ arguments: Arguments) throws {
        try arguments.rejectUnknown(["--private-key", "--public-key"])
        let privateURL = URL(fileURLWithPath: try arguments.one("--private-key"))
        let publicURL = URL(fileURLWithPath: try arguments.one("--public-key"))
        let privateKey = Curve25519.Signing.PrivateKey()
        try writePrivateKey(privateKey.rawRepresentation, to: privateURL)
        try writePublicKey(privateKey.publicKey.rawRepresentation, to: publicURL)
        print(keyID(for: privateKey.publicKey.rawRepresentation))
    }

    private static func exportPublic(_ arguments: Arguments) throws {
        try arguments.rejectUnknown(["--private-key", "--public-key"])
        let privateKey = try readPrivateKey(
            at: URL(fileURLWithPath: try arguments.one("--private-key"))
        )
        let publicBytes = privateKey.publicKey.rawRepresentation
        try writePublicKey(
            publicBytes,
            to: URL(fileURLWithPath: try arguments.one("--public-key"))
        )
        print(keyID(for: publicBytes))
    }

    private static func sign(_ arguments: Arguments) throws {
        try arguments.rejectUnknown(["--catalog", "--output", "--signing-key"])
        let catalogURL = URL(fileURLWithPath: try arguments.one("--catalog"))
        let outputURL = URL(fileURLWithPath: try arguments.one("--output"))
        let catalogData = try Data(contentsOf: catalogURL, options: .mappedIfSafe)
        guard !catalogData.isEmpty, catalogData.count <= maximumCatalogBytes else {
            throw ToolError.invalidCatalog
        }
        let keySpecifications = try arguments.many("--signing-key")
        guard keySpecifications.count <= maximumSignatures else {
            throw ToolError.invalidEnvelope
        }
        var seen = Set<String>()
        var signatures: [DetachedSignature] = []
        for specification in keySpecifications {
            guard let separator = specification.firstIndex(of: "=") else {
                throw ToolError.usage
            }
            let suppliedID = String(specification[..<separator])
            let path = String(specification[specification.index(after: separator)...])
            guard !suppliedID.isEmpty, !path.isEmpty, seen.insert(suppliedID).inserted else {
                throw ToolError.invalidEnvelope
            }
            let privateKey = try readPrivateKey(at: URL(fileURLWithPath: path))
            let actualID = keyID(for: privateKey.publicKey.rawRepresentation)
            guard suppliedID == actualID else {
                throw ToolError.keyIDMismatch(expected: actualID, actual: suppliedID)
            }
            signatures.append(
                DetachedSignature(
                    keyID: suppliedID,
                    signature: try privateKey.signature(for: catalogData)
                        .base64EncodedString()
                )
            )
        }
        signatures.sort { $0.keyID < $1.keyID }
        let envelope = SignatureEnvelope(
            schemaVersion: 1,
            algorithm: "Ed25519",
            catalogSHA256: sha256(catalogData),
            catalogByteCount: catalogData.count,
            signatures: signatures
        )
        let data = try encoded(envelope)
        guard data.count <= maximumEnvelopeBytes else {
            throw ToolError.invalidEnvelope
        }
        try writePublicArtifact(data, to: outputURL)
        print("signed \(catalogData.count) bytes with \(signatures.count) key(s)")
    }

    private static func verify(_ arguments: Arguments) throws {
        try arguments.rejectUnknown(["--catalog", "--signature", "--public-key"])
        let catalogData = try Data(
            contentsOf: URL(fileURLWithPath: try arguments.one("--catalog")),
            options: .mappedIfSafe
        )
        guard !catalogData.isEmpty, catalogData.count <= maximumCatalogBytes else {
            throw ToolError.invalidCatalog
        }
        let signatureData = try Data(
            contentsOf: URL(fileURLWithPath: try arguments.one("--signature"))
        )
        let envelope = try decodeEnvelope(signatureData)
        guard envelope.catalogByteCount == catalogData.count,
              envelope.catalogSHA256 == sha256(catalogData) else {
            throw ToolError.invalidEnvelope
        }
        var publicKeys: [String: Curve25519.Signing.PublicKey] = [:]
        for path in try arguments.many("--public-key") {
            let document = try decodePublicKey(at: URL(fileURLWithPath: path))
            guard publicKeys[document.keyID] == nil,
                  let raw = canonicalBase64(document.publicKey),
                  raw.count == 32,
                  keyID(for: raw) == document.keyID else {
                throw ToolError.invalidKey(path)
            }
            publicKeys[document.keyID] = try Curve25519.Signing.PublicKey(
                rawRepresentation: raw
            )
        }
        let valid = envelope.signatures.contains { detached in
            guard let key = publicKeys[detached.keyID],
                  let signature = canonicalBase64(detached.signature),
                  signature.count == 64 else { return false }
            return key.isValidSignature(signature, for: catalogData)
        }
        guard valid else { throw ToolError.noTrustedSignature }
        print("verified \(catalogData.count) exact catalog bytes")
    }
}

private func readPrivateKey(at url: URL) throws -> Curve25519.Signing.PrivateKey {
    guard !isInsideGitWorkingTree(url) else {
        throw ToolError.unsafePrivateKey("private keys must remain outside Git working trees")
    }
    let descriptor = url.path.withCString {
        Darwin.open($0, O_RDONLY | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
        throw ToolError.unsafePrivateKey(url.path)
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var status = stat()
    guard Darwin.fstat(descriptor, &status) == 0,
          (status.st_mode & S_IFMT) == S_IFREG,
          status.st_uid == getuid(),
          status.st_nlink == 1,
          Int(status.st_mode & 0o777) == 0o600,
          status.st_size > 0,
          status.st_size <= 128 else {
        throw ToolError.unsafePrivateKey(url.path)
    }
    let keyData = try handle.readToEnd() ?? Data()
    guard keyData.count == Int(status.st_size),
          let keyText = String(data: keyData, encoding: .utf8) else {
        throw ToolError.invalidKey(url.path)
    }
    let encoded = keyText
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw = canonicalBase64(encoded), raw.count == 32 else {
        throw ToolError.invalidKey(url.path)
    }
    return try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
}

private func writePrivateKey(_ raw: Data, to url: URL) throws {
    guard !isInsideGitWorkingTree(url) else {
        throw ToolError.unsafePrivateKey("private keys must remain outside Git working trees")
    }
    guard !FileManager.default.fileExists(atPath: url.path) else {
        throw ToolError.outputExists(url.path)
    }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let descriptor = url.path.withCString {
        Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    }
    guard descriptor >= 0 else { throw ToolError.unsafePrivateKey(url.path) }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do {
        try handle.write(contentsOf: Data((raw.base64EncodedString() + "\n").utf8))
        try handle.synchronize()
        try handle.close()
    } catch {
        try? FileManager.default.removeItem(at: url)
        throw error
    }
}

private func isInsideGitWorkingTree(_ url: URL) -> Bool {
    var candidate = url.standardizedFileURL.deletingLastPathComponent()
    while true {
        if FileManager.default.fileExists(
            atPath: candidate.appendingPathComponent(".git").path
        ) {
            return true
        }
        let parent = candidate.deletingLastPathComponent()
        if parent.path == candidate.path { return false }
        candidate = parent
    }
}

private func writePublicKey(_ raw: Data, to url: URL) throws {
    let document = PublicKeyDocument(
        schemaVersion: 1,
        algorithm: "Ed25519",
        keyID: keyID(for: raw),
        publicKey: raw.base64EncodedString()
    )
    try writePublicArtifact(try encoded(document), to: url)
}

private func writePublicArtifact(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
}

private func decodeEnvelope(_ data: Data) throws -> SignatureEnvelope {
    guard !data.isEmpty, data.count <= maximumEnvelopeBytes,
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          Set(root.keys) == [
              "schemaVersion", "algorithm", "catalogSHA256",
              "catalogByteCount", "signatures",
          ],
          let entries = root["signatures"] as? [Any],
          !entries.isEmpty,
          entries.count <= maximumSignatures,
          entries.allSatisfy({ value in
              guard let object = value as? [String: Any] else { return false }
              return Set(object.keys) == ["keyID", "signature"]
          }),
          let envelope = try? JSONDecoder().decode(SignatureEnvelope.self, from: data),
          envelope.schemaVersion == 1,
          envelope.algorithm == "Ed25519",
          envelope.catalogSHA256.count == 64 else {
        throw ToolError.invalidEnvelope
    }
    var keyIDs = Set<String>()
    guard envelope.signatures.allSatisfy({ detached in
        keyIDs.insert(detached.keyID).inserted
            && canonicalBase64(detached.signature)?.count == 64
    }) else {
        throw ToolError.invalidEnvelope
    }
    return envelope
}

private func decodePublicKey(at url: URL) throws -> PublicKeyDocument {
    let data = try Data(contentsOf: url)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          Set(root.keys) == ["schemaVersion", "algorithm", "keyID", "publicKey"],
          let document = try? JSONDecoder().decode(PublicKeyDocument.self, from: data),
          document.schemaVersion == 1,
          document.algorithm == "Ed25519" else {
        throw ToolError.invalidKey(url.path)
    }
    return document
}

private func canonicalBase64(_ value: String) -> Data? {
    guard let data = Data(base64Encoded: value),
          data.base64EncodedString() == value else { return nil }
    return data
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func keyID(for publicKey: Data) -> String {
    "ed25519-" + String(sha256(publicKey).prefix(16))
}

private func encoded<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(value)
    data.append(0x0a)
    return data
}
