import SwanSongKit
import XCTest

final class TranslationLabAutomationTests: XCTestCase {
    func testFrameInputPlanResolvesDeterministicInputTimeline() throws {
        let plan = TranslationFrameInputPlan(
            totalFrames: 120,
            events: [
                TranslationFrameInputPlanEvent(frameIndex: 0, inputs: []),
                TranslationFrameInputPlanEvent(frameIndex: 30, inputs: ["a", "x1"]),
                TranslationFrameInputPlanEvent(frameIndex: 45, inputs: ["x1"]),
                TranslationFrameInputPlanEvent(frameIndex: 60, inputs: []),
            ]
        )

        try plan.validate(for: .wonderSwanColor)

        XCTAssertEqual(try plan.input(at: 0).rawValue, 0)
        XCTAssertEqual(
            try plan.input(at: 30).rawValue,
            EngineInput.a.rawValue | EngineInput.x1.rawValue
        )
        XCTAssertEqual(try plan.input(at: 59).rawValue, EngineInput.x1.rawValue)
        XCTAssertEqual(try plan.input(at: 60).rawValue, 0)
    }

    func testFrameInputPlanRequiresExplicitFrameZeroAndBoundedRun() {
        XCTAssertThrowsError(
            try TranslationFrameInputPlan(
                totalFrames: 2,
                events: [TranslationFrameInputPlanEvent(frameIndex: 0, inputs: [])]
            ).validate(for: .wonderSwan)
        )
        XCTAssertThrowsError(
            try TranslationFrameInputPlan(
                totalFrames: 60,
                events: [TranslationFrameInputPlanEvent(frameIndex: 1, inputs: [])]
            ).validate(for: .wonderSwan)
        )
    }

    func testFrameInputPlanRejectsUnknownAndRepeatedControls() {
        XCTAssertThrowsError(
            try TranslationFrameInputPlan(
                totalFrames: 60,
                events: [
                    TranslationFrameInputPlanEvent(frameIndex: 0, inputs: ["turbo"]),
                ]
            ).validate(for: .wonderSwan)
        )
        XCTAssertThrowsError(
            try TranslationFrameInputPlan(
                totalFrames: 60,
                events: [
                    TranslationFrameInputPlanEvent(frameIndex: 0, inputs: ["a", "a"]),
                ]
            ).validate(for: .wonderSwan)
        )
    }

    func testFrameInputPlanKeepsWonderSwanAndPocketControlsSeparate() {
        let pocket = TranslationFrameInputPlan(
            totalFrames: 60,
            events: [
                TranslationFrameInputPlanEvent(
                    frameIndex: 0,
                    inputs: ["pocket-circle"]
                ),
            ]
        )
        XCTAssertNoThrow(try pocket.validate(for: .pocketChallengeV2))
        XCTAssertThrowsError(try pocket.validate(for: .wonderSwan))
    }

    func testFrameInputPlanRoundTripsItsVersionedSchema() throws {
        let plan = TranslationFrameInputPlan(
            totalFrames: 90,
            events: [TranslationFrameInputPlanEvent(frameIndex: 0, inputs: ["start"])]
        )

        let decoded = try JSONDecoder().decode(
            TranslationFrameInputPlan.self,
            from: JSONEncoder().encode(plan)
        )

        XCTAssertEqual(decoded, plan)
        XCTAssertEqual(decoded.schema, TranslationFrameInputPlan.currentSchema)
    }
}
