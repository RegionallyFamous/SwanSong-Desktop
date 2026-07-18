import AppKit
import Foundation
import UserNotifications

enum SwanSongTaskCompletionResult: Equatable, Sendable {
    case succeeded
    case failed
}

struct SwanSongTaskCompletion: Equatable, Sendable {
    let name: String
    let result: SwanSongTaskCompletionResult
}

struct SwanSongTaskNotificationContent: Equatable, Sendable {
    let title: String
    let body: String
}

enum SwanSongTaskNotificationPolicy {
    static func shouldDeliver(isEnabled: Bool, isApplicationActive: Bool) -> Bool {
        isEnabled && !isApplicationActive
    }

    static func content(for completion: SwanSongTaskCompletion) -> SwanSongTaskNotificationContent {
        switch completion.result {
        case .succeeded:
            SwanSongTaskNotificationContent(
                title: "\(completion.name) finished",
                body: "SwanSong Studio completed the task successfully."
            )
        case .failed:
            SwanSongTaskNotificationContent(
                title: "\(completion.name) needs attention",
                body: "Open SwanSong Studio to review the task details."
            )
        }
    }
}

@MainActor
final class SwanSongTaskNotificationCenter {
    static let shared = SwanSongTaskNotificationCenter()
    static let enabledDefaultsKey = "SwanSong.taskCompletionNotificationsEnabled"

    private let defaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter
    private let isApplicationActive: () -> Bool

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: UNUserNotificationCenter = .current(),
        isApplicationActive: @escaping () -> Bool = { NSApp.isActive }
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.isApplicationActive = isApplicationActive
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledDefaultsKey)
    }

    @discardableResult
    func setEnabled(_ requested: Bool) async -> Bool {
        guard requested else {
            defaults.set(false, forKey: Self.enabledDefaultsKey)
            return false
        }
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound]
            )
            defaults.set(granted, forKey: Self.enabledDefaultsKey)
            return granted
        } catch {
            defaults.set(false, forKey: Self.enabledDefaultsKey)
            return false
        }
    }

    func deliver(_ completion: SwanSongTaskCompletion) {
        guard SwanSongTaskNotificationPolicy.shouldDeliver(
            isEnabled: isEnabled,
            isApplicationActive: isApplicationActive()
        ) else { return }

        let description = SwanSongTaskNotificationPolicy.content(for: completion)
        let content = UNMutableNotificationContent()
        content.title = description.title
        content.body = description.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "studio-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request)
    }
}
