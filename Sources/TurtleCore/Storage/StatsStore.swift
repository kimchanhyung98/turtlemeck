import Foundation

public struct DailyPostureStats: Codable, Equatable, Sendable {
    public var day: String
    public var cautionTransitions: Int
    public var recoveries: Int
    public var notificationsSent: Int
    public var goodSeconds: Int
    public var badSeconds: Int

    public init(
        day: String,
        cautionTransitions: Int = 0,
        recoveries: Int = 0,
        notificationsSent: Int = 0,
        goodSeconds: Int = 0,
        badSeconds: Int = 0
    ) {
        self.day = day
        self.cautionTransitions = cautionTransitions
        self.recoveries = recoveries
        self.notificationsSent = notificationsSent
        self.goodSeconds = goodSeconds
        self.badSeconds = badSeconds
    }

    enum CodingKeys: String, CodingKey {
        case day
        case cautionTransitions
        case recoveries
        case notificationsSent
        case goodSeconds
        case badSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        cautionTransitions = try container.decodeIfPresent(Int.self, forKey: .cautionTransitions) ?? 0
        recoveries = try container.decodeIfPresent(Int.self, forKey: .recoveries) ?? 0
        notificationsSent = try container.decodeIfPresent(Int.self, forKey: .notificationsSent) ?? 0
        goodSeconds = try container.decodeIfPresent(Int.self, forKey: .goodSeconds) ?? 0
        badSeconds = try container.decodeIfPresent(Int.self, forKey: .badSeconds) ?? 0
    }

    public mutating func record(_ event: AlertEvent) {
        switch event {
        case .cautionStarted:
            cautionTransitions += 1
        case .recovered:
            recoveries += 1
        }
    }

    public mutating func recordNotificationSent() {
        notificationsSent += 1
    }

    public mutating func recordDuration(state: PostureState, seconds: Int) {
        let seconds = max(0, seconds)
        switch state {
        case .good:
            goodSeconds += seconds
        case .bad:
            badSeconds += seconds
        case .calibrating, .noEval, .paused, .blocked:
            break
        }
    }
}

public final class StatsStore {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = support.appendingPathComponent("turtlemeck", isDirectory: true).appendingPathComponent("stats.json")
        }
    }

    public func load() throws -> [DailyPostureStats] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([DailyPostureStats].self, from: data)
    }

    public func save(_ stats: [DailyPostureStats]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(stats)
        try data.write(to: fileURL, options: [.atomic])
    }
}
