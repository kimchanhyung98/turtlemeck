import AppKit
import Foundation
import UserNotifications

public final class NotificationManager {
    private var messages = PostureReminderMessages()

    public init() {}

    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func sendPostureReminder(
        bannerEnabled: Bool,
        soundEnabled: Bool,
        completion: @escaping @Sendable (Bool) -> Void = { _ in }
    ) {
        guard bannerEnabled else {
            // 배너 없이 소리만 켠 경우 시스템 경고음만 재생한다.
            guard soundEnabled else {
                completion(false)
                return
            }
            NSSound.beep()
            completion(true)
            return
        }
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
