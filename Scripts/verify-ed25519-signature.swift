#!/usr/bin/env swift
import CryptoKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write(
        Data("usage: verify-ed25519-signature.swift PUBLIC_KEY FILE SIGNATURE\n".utf8)
    )
    exit(64)
}

let publicKeyString = CommandLine.arguments[1]
let fileURL = URL(fileURLWithPath: CommandLine.arguments[2])
let signatureString = CommandLine.arguments[3]

do {
    guard let publicKeyData = Data(base64Encoded: publicKeyString),
          publicKeyData.count == 32,
          let signatureData = Data(base64Encoded: signatureString),
          signatureData.count == 64 else {
        throw NSError(domain: "SwanSongSparkleSignature", code: 1)
    }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let payload = try Data(contentsOf: fileURL, options: .mappedIfSafe)
    guard publicKey.isValidSignature(signatureData, for: payload) else {
        throw NSError(domain: "SwanSongSparkleSignature", code: 2)
    }
    print("PASS Ed25519 signature matches SwanSong's committed Sparkle public key")
} catch {
    FileHandle.standardError.write(
        Data("Ed25519 signature verification failed\n".utf8)
    )
    exit(1)
}
