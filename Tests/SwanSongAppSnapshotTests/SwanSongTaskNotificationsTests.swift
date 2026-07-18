import XCTest
@testable import SwanSongApp

final class SwanSongTaskNotificationsTests: XCTestCase {
    func testPolicyDeliversOnlyWhenEnabledAndBackgrounded() {
        XCTAssertTrue(
            SwanSongTaskNotificationPolicy.shouldDeliver(
                isEnabled: true,
                isApplicationActive: false
            )
        )
        XCTAssertFalse(
            SwanSongTaskNotificationPolicy.shouldDeliver(
                isEnabled: false,
                isApplicationActive: false
            )
        )
        XCTAssertFalse(
            SwanSongTaskNotificationPolicy.shouldDeliver(
                isEnabled: true,
                isApplicationActive: true
            )
        )
    }

    func testSuccessfulTaskUsesSourceFreeMessage() {
        let content = SwanSongTaskNotificationPolicy.content(
            for: SwanSongTaskCompletion(name: "Build", result: .succeeded)
        )
        XCTAssertEqual(content.title, "Build finished")
        XCTAssertEqual(
            content.body,
            "SwanSong Studio completed the task successfully."
        )
        XCTAssertFalse(content.body.localizedCaseInsensitiveContains("path"))
        XCTAssertFalse(content.body.localizedCaseInsensitiveContains("ROM"))
    }

    func testFailedTaskAsksForAttentionWithoutLeakingDiagnostics() {
        let content = SwanSongTaskNotificationPolicy.content(
            for: SwanSongTaskCompletion(name: "Release", result: .failed)
        )
        XCTAssertEqual(content.title, "Release needs attention")
        XCTAssertEqual(content.body, "Open SwanSong Studio to review the task details.")
    }
}
