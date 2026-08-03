import XCTest
@testable import SwanSongKit

final class TranslationOriginalFrameAuthenticationStageTests: XCTestCase {
    func testCategoriesAreExactAndStable() {
        XCTAssertEqual(
            TranslationOriginalFrameAuthenticationStage.allCases.map(\.rawValue),
            [
                "authorization",
                "executor-observation",
                "bound-input-project-tree-observation",
                "run-tree-observation",
                "pre-seal-assembly",
                "project",
                "plan",
                "authentication",
                "engine",
                "query",
                "inspect",
                "load",
                "run",
                "frame",
                "raster",
                "endpoint",
                "geometry",
                "revalidation",
                "output",
            ]
        )
    }

    func testPublicNegativeControlsPublishOnlyTheirStage() throws {
        let privateDecoy =
            "private-path=/never/share/private.rom address=0x1234"
        for stage in TranslationOriginalFrameAuthenticationStage.allCases {
            XCTAssertThrowsError(
                try stage.perform { () throws -> Void in
                    throw NSError(
                        domain: privateDecoy,
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: privateDecoy,
                        ]
                    )
                }
            ) { error in
                guard let failure = error
                    as? TranslationOriginalFrameAuthenticationStageFailure
                else {
                    return XCTFail("unexpected failure type \(error)")
                }
                XCTAssertEqual(failure.stage, stage)
                XCTAssertEqual(
                    failure.errorDescription,
                    "STOP_PREEXECUTION_CAPABILITY: \(stage.marker)"
                )
                XCTAssertFalse(
                    failure.errorDescription?.contains(privateDecoy) ?? true
                )
            }
            XCTAssertEqual(
                TranslationOriginalFrameAuthenticationStage
                    .sourceFreeCategory(
                        in: "private \(privateDecoy) \(stage.marker)"
                    ),
                stage
            )
        }
    }

    func testUnknownAndAmbiguousOutputRemainUnclassified() {
        XCTAssertNil(
            TranslationOriginalFrameAuthenticationStage
                .sourceFreeCategory(in: "private runner failure")
        )
        XCTAssertNil(
            TranslationOriginalFrameAuthenticationStage.sourceFreeCategory(
                in: TranslationOriginalFrameAuthenticationStage.markerPrefix
            )
        )
        XCTAssertNil(
            TranslationOriginalFrameAuthenticationStage.sourceFreeCategory(
                in: TranslationOriginalFrameAuthenticationStage.markerPrefix
                    + "unknown-private-stage"
            )
        )
        XCTAssertNil(
            TranslationOriginalFrameAuthenticationStage.sourceFreeCategory(
                in: [
                    TranslationOriginalFrameAuthenticationStage.inspect.marker,
                    TranslationOriginalFrameAuthenticationStage.load.marker,
                ].joined(separator: " ")
            )
        )
    }

    func testSignedReleaseStageKAT() throws {
        XCTAssertEqual(
            try TranslationOriginalFrameAuthenticationStage
                .signedReleaseSourceFreeStageKAT(),
            "PASS original-frame-stage-categories "
                + "authorization,executor-observation,"
                + "bound-input-project-tree-observation,"
                + "run-tree-observation,pre-seal-assembly,"
                + "project,plan,authentication,engine,query,inspect,load,"
                + "run,frame,raster,endpoint,geometry,revalidation,output"
        )
    }
}
