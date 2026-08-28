import Foundation

public enum NotchIndicatorSide: String, Codable, Equatable, Sendable {
    case left
    case right
}

public enum NotchIndicatorPlacement: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case left
    case right
    case both

    public var sides: [NotchIndicatorSide] {
        switch self {
        case .none:
            return []
        case .left:
            return [.left]
        case .right:
            return [.right]
        case .both:
            return [.left, .right]
        }
    }
}

public struct Settings: Codable, Equatable, Sendable {
    private var storedCheckIntervalSeconds: Int
    public var bannerNotificationsEnabled: Bool
    public var notificationSoundEnabled: Bool
    public var notchIndicatorPlacement: NotchIndicatorPlacement
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

    public var activeNotchIndicatorSides: [NotchIndicatorSide] {
        notchIndicatorPlacement.sides
    }

    public init(
        checkIntervalSeconds: Int,
        bannerNotificationsEnabled: Bool,
        notificationSoundEnabled: Bool,
        launchAtLogin: Bool,
        notchIndicatorPlacement: NotchIndicatorPlacement = .none,
        debugEnabled: Bool = false,
        baseline: Baseline? = nil
    ) {
        self.storedCheckIntervalSeconds = Self.clampInterval(checkIntervalSeconds)
        self.bannerNotificationsEnabled = bannerNotificationsEnabled
        self.notificationSoundEnabled = notificationSoundEnabled
        self.notchIndicatorPlacement = notchIndicatorPlacement
        self.launchAtLogin = launchAtLogin
        self.debugEnabled = debugEnabled
        self.baseline = baseline
    }

    public static let defaults = Settings(
        checkIntervalSeconds: 60,
        bannerNotificationsEnabled: false,
        notificationSoundEnabled: false,
        launchAtLogin: false,
        notchIndicatorPlacement: .none
    )

    private enum CodingKeys: String, CodingKey {
        case storedCheckIntervalSeconds
        case bannerNotificationsEnabled
        case notificationSoundEnabled
        case legacyNotchIndicatorEnabled = "notchIndicatorEnabled"
        case notchIndicatorPlacement
        case launchAtLogin
        case debugEnabled
        case baseline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storedCheckIntervalSeconds = Self.clampInterval(try container.decode(Int.self, forKey: .storedCheckIntervalSeconds))
        bannerNotificationsEnabled = try container.decode(Bool.self, forKey: .bannerNotificationsEnabled)
        notificationSoundEnabled = try container.decode(Bool.self, forKey: .notificationSoundEnabled)
        let legacyEnabled = try? container.decode(Bool.self, forKey: .legacyNotchIndicatorEnabled)
        let decodedPlacement = try? container.decode(NotchIndicatorPlacement.self, forKey: .notchIndicatorPlacement)
        if legacyEnabled == false {
            notchIndicatorPlacement = .none
        } else if let decodedPlacement {
            notchIndicatorPlacement = decodedPlacement
        } else if legacyEnabled == true {
            notchIndicatorPlacement = .right
        } else {
            notchIndicatorPlacement = .none
        }
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        debugEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .debugEnabled)) ?? false
        // 이전 특성 버전의 기준값은 현재 특성값과 비교할 수 없어 폐기한다.
        let decodedBaseline = (try? container.decodeIfPresent(Baseline.self, forKey: .baseline)) ?? nil
        baseline = decodedBaseline?.featureVersion == Baseline.currentFeatureVersion ? decodedBaseline : nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(checkIntervalSeconds, forKey: .storedCheckIntervalSeconds)
        try container.encode(bannerNotificationsEnabled, forKey: .bannerNotificationsEnabled)
        try container.encode(notificationSoundEnabled, forKey: .notificationSoundEnabled)
        try container.encode(notchIndicatorPlacement, forKey: .notchIndicatorPlacement)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(debugEnabled, forKey: .debugEnabled)
        try container.encodeIfPresent(baseline, forKey: .baseline)
    }

    private static func clampInterval(_ value: Int) -> Int {
        min(180, max(15, value))
    }
}
