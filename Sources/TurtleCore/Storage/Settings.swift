import Foundation

public struct Settings: Codable, Equatable, Sendable {
    private var storedCheckIntervalSeconds: Int
    public var bannerNotificationsEnabled: Bool
    public var notificationSoundEnabled: Bool
    public var launchAtLogin: Bool
    public var debugEnabled: Bool
    public var baseline: Baseline?

    public var checkIntervalSeconds: Int {
        get {
            storedCheckIntervalSeconds
        }
        set {
            storedCheckIntervalSeconds = Self.clampInterval(newValue)
        }
    }

    public init(
        checkIntervalSeconds: Int,
        bannerNotificationsEnabled: Bool,
        notificationSoundEnabled: Bool,
        launchAtLogin: Bool,
        debugEnabled: Bool = false,
        baseline: Baseline? = nil
    ) {
        self.storedCheckIntervalSeconds = Self.clampInterval(checkIntervalSeconds)
        self.bannerNotificationsEnabled = bannerNotificationsEnabled
        self.notificationSoundEnabled = notificationSoundEnabled
        self.launchAtLogin = launchAtLogin
        self.debugEnabled = debugEnabled
        self.baseline = baseline
    }

    public static let defaults = Settings(
        checkIntervalSeconds: 60,
        bannerNotificationsEnabled: false,
        notificationSoundEnabled: false,
        launchAtLogin: false
    )

    private enum CodingKeys: String, CodingKey {
        case storedCheckIntervalSeconds
        case bannerNotificationsEnabled
        case notificationSoundEnabled
        case launchAtLogin
        case debugEnabled
        case baseline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storedCheckIntervalSeconds = Self.clampInterval(try container.decode(Int.self, forKey: .storedCheckIntervalSeconds))
        bannerNotificationsEnabled = try container.decode(Bool.self, forKey: .bannerNotificationsEnabled)
        notificationSoundEnabled = try container.decode(Bool.self, forKey: .notificationSoundEnabled)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        debugEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .debugEnabled)) ?? false
        // 이전 다중 알고리즘 baseline은 현재 단일 relative-depth 계약과 호환되지 않으므로 재보정한다.
        baseline = (try? container.decodeIfPresent(Baseline.self, forKey: .baseline)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(checkIntervalSeconds, forKey: .storedCheckIntervalSeconds)
        try container.encode(bannerNotificationsEnabled, forKey: .bannerNotificationsEnabled)
        try container.encode(notificationSoundEnabled, forKey: .notificationSoundEnabled)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(debugEnabled, forKey: .debugEnabled)
        try container.encodeIfPresent(baseline, forKey: .baseline)
    }

    private static func clampInterval(_ value: Int) -> Int {
        min(180, max(15, value))
    }
}
