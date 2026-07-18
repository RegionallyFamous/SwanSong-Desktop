import Foundation
@testable import SwanSongKit
import XCTest

final class PublishedHomebrewCatalogTests: XCTestCase {
    func testRightsAttestedCatalogMapsToInstallablePresentationModel() throws {
        let catalog = try PublishedHomebrewCatalogDecoder.decode(
            fixture(),
            sourceURL: PublishedHomebrewCatalogDecoder.sourceURL
        )

        XCTAssertEqual(catalog.catalogID, PublishedHomebrewCatalogDecoder.catalogID)
        XCTAssertEqual(catalog.revision, 1)
        let entry = try XCTUnwrap(catalog.entries.first)
        let release = try XCTUnwrap(entry.releases.first)
        XCTAssertEqual(entry.developer, "Regionally Famous")
        XCTAssertEqual(entry.licenseName, "MIT")
        XCTAssertEqual(release.asset.byteCount, 131_072)
        XCTAssertEqual(release.asset.hardwareModel, .wonderSwanColor)
        XCTAssertNoThrow(
            try HomebrewCatalogValidator.validateForInstallation(
                entry: entry,
                release: release,
                catalogID: catalog.catalogID
            )
        )
    }

    func testRightsOrUnknownWireFieldsFailClosed() throws {
        let denied = fixture().replacingOccurrences(
            of: #""authorizedForRedistribution":true"#,
            with: #""authorizedForRedistribution":false"#
        )
        XCTAssertThrowsError(
            try PublishedHomebrewCatalogDecoder.decode(
                Data(denied.utf8),
                sourceURL: PublishedHomebrewCatalogDecoder.sourceURL
            )
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixture()) as? [String: Any]
        )
        var changed = object
        changed["script"] = "do-not-run"
        XCTAssertThrowsError(
            try PublishedHomebrewCatalogDecoder.decode(
                try JSONSerialization.data(withJSONObject: changed),
                sourceURL: PublishedHomebrewCatalogDecoder.sourceURL
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogError,
                .invalidJSONSchema("document")
            )
        }
    }

    private func fixture() -> Data {
        Data(#"""
        {
          "schema":"swansong-homebrew-catalog-v1",
          "catalogVersion":1,
          "entries":[{
            "content":{"ageRating":"Everyone","network":false,"purchases":false},
            "controls":["Directions move"],
            "evidence":"https://github.com/RegionallyFamous/SwanSong-Originals/blob/v3.0.0/docs/STATUS.md",
            "format":"wsc","hardware":["wonderswan-color"],"id":"orbital-courier",
            "orientation":"horizontal","players":1,"publisher":"regionally-famous",
            "rights":{"authorizedForRedistribution":true,"originalWork":true,"publisherSuppliedScreenshot":true},
            "rom":{"bytes":131072,"sha256":"ed29e214e562de79639652f2afe2122a267b49d4870ee5abd64f6d7c4f1feafe","url":"https://github.com/RegionallyFamous/SwanSong-Originals/releases/download/v3.0.0/orbital_courier.wsc"},
            "screenshot":"https://raw.githubusercontent.com/RegionallyFamous/SwanSong-Originals/v3.0.0/docs/qa/native-frames/orbital_courier.png",
            "source":{"license":"MIT","revision":"v3.0.0","url":"https://github.com/RegionallyFamous/SwanSong-Originals"},
            "summary":"Collect a parcel and route through an obstacle grid.",
            "title":"Orbital Courier","version":"3.0.0"
          }],
          "publishers":[{"attestsDistributionRights":true,"controlsRelease":true,"id":"regionally-famous","name":"Regionally Famous","url":"https://github.com/RegionallyFamous"}],
          "sourceFiles":[{"path":"swansong-originals-v3.json","sha256":"4bab8f9bcf6ae55b626b5f25529c5af26c2d48761980d9c046a4fc1588fe8ab7"}]
        }
        """#.utf8)
    }
}

private extension Data {
    func replacingOccurrences(of target: String, with replacement: String) -> String {
        String(decoding: self, as: UTF8.self)
            .replacingOccurrences(of: target, with: replacement)
    }
}
