import Foundation
import UserNotifications

public final class NotificationManager {
    private var messages = PostureReminderMessages()

    public init() {}

    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func sendPostureReminder(soundEnabled: Bool, completion: @escaping @Sendable (Bool) -> Void = { _ in }) {
        let content = UNMutableNotificationContent()
        content.title = "turtlemeck"
        content.body = messages.nextBody()
        content.interruptionLevel = .passive
        if soundEnabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "com.go.turtlemeck.posture.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            completion(error == nil)
        }
    }
}
