import XCTest
@testable import SwanSongApp

final class ControllerBatterySummaryTests: XCTestCase {
    func testLevelIsClampedAndRoundedForDisplay() {
        XCTAssertEqual(
            ControllerBatterySummary(level: 1.4, state: .discharging).percentage,
            100
        )
        XCTAssertEqual(
            ControllerBatterySummary(level: -0.5, state: .unknown).percentage,
            0
        )
        XCTAssertEqual(
            ControllerBatterySummary(level: 0.746, state: .discharging).percentage,
            75
        )
    }

    func testLowBatteryWarningRequiresDischargingState() {
        XCTAssertTrue(
            ControllerBatterySummary(level: 0.2, state: .discharging).isLow
        )
        XCTAssertFalse(
            ControllerBatterySummary(level: 0.2, state: .charging).isLow
        )
        XCTAssertFalse(
            ControllerBatterySummary(level: 0.21, state: .discharging).isLow
        )
    }

    func testChargingAndFullStatesHaveClearAccessibleCopy() {
        let charging = ControllerBatterySummary(level: 0.42, state: .charging)
        XCTAssertEqual(charging.statusText, "42% · Charging")
        XCTAssertEqual(charging.symbolName, "battery.100percent.bolt")

        let full = ControllerBatterySummary(level: 0.98, state: .full)
        XCTAssertEqual(full.statusText, "100% · Fully charged")
        XCTAssertEqual(full.symbolName, "battery.100percent")
    }
}
