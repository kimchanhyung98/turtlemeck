import Foundation

public struct NotificationPolicy {
    private let minimumInterval: TimeInterval
    private var lastCautionDate: Date?
    private var snoozeUntil: Date?

    public init(minimumInterval: TimeInterval = 25 * 60) {
        self.minimumInterval = minimumInterval
    }

    public mutating func shouldSend(alert: AlertEvent, at date: Date = Date()) -> Bool {
        guard alert == .cautionStarted else {
            return false
        }

        if let snoozeUntil, date < snoozeUntil {
            return false
        }

        if let lastCautionDate, date.timeIntervalSince(lastCautionDate) < minimumInterval {
            return false
        }

        lastCautionDate = date
        return true
    }

    public mutating func snooze(until date: Date) {
        snoozeUntil = date
    }
}

public struct PostureReminderMessages {
    private let messages = [
        "자세를 한 번 펴볼까요",
        "턱을 살짝 당기고 화면을 바라볼까요",
        "어깨를 펴고 목을 편하게 세워볼까요",
        "고개가 앞으로 나왔어요. 등을 펴볼까요",
        "지금 자세를 한 번 점검해볼 타이밍이에요"
    ]
    private var index = 0

    public init() {}

    public mutating func nextBody() -> String {
        let body = messages[index % messages.count]
        index += 1
        return body
    }
}
