import CryptoKit
import Foundation
@testable import SwanSongKit
import XCTest

final class SwanSongAuthorizedPathPolicyTests: XCTestCase {
    func testPrivateTmpSpellingSurvivesExistingAndFutureCanonicalization() throws {
        let privateTmp = try SwanSongAuthorizedPathPolicy.canonicalExistingPath(
            "/private/tmp"
        )
        XCTAssertEqual(privateTmp, "/private/tmp")
        XCTAssertEqual(
            SHA256.hash(data: Data(privateTmp.utf8))
                .map { String(format: "%02x", $0) }
                .joined(),
            "11fe14a563f7aed66191800dc08fe0d15049ef7d9dac5f5ab4b0ca20b28e193d"
        )
        XCTAssertThrowsError(
            try SwanSongAuthorizedPathPolicy.canonicalExistingPath("/tmp")
        )

        let parent = "/private/tmp/swan-song-path-policy-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: parent,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(atPath: parent) }
        let future = "\(parent)/report.json"
        XCTAssertEqual(
            try SwanSongAuthorizedPathPolicy.canonicalFuturePath(future),
            future
        )
        XCTAssertThrowsError(
            try SwanSongAuthorizedPathPolicy.canonicalFuturePath(
                future.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
            )
        )
    }
}
