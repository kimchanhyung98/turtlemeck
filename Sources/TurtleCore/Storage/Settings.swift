import Foundation

public struct Settings: Codable, Equatable, Sendable {
    private var storedCheckIntervalSeconds: Int
    public var postureAlgorithm: PostureAlgorithmID
    public var sensitivity: Sensitivity
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
        postureAlgorithm: PostureAlgorithmID = .fusion,
        sensitivity: Sensitivity,
        bannerNotificationsEnabled: Bool,
        notificationSoundEnabled: Bool,
        launchAtLogin: Bool,
        debugEnabled: Bool = false,
        baseline: Baseline? = nil
    ) {
        self.storedCheckIntervalSeconds = Self.clampInterval(checkIntervalSeconds)
        self.postureAlgorithm = postureAlgorithm
        self.sensitivity = sensitivity
        self.bannerNotificationsEnabled = bannerNotificationsEnabled
        self.notificationSoundEnabled = notificationSoundEnabled
        self.launchAtLogin = launchAtLogin
        self.debugEnabled = debugEnabled
        self.baseline = baseline
    }

    public static let defaults = Settings(
        checkIntervalSeconds: 60,
        postureAlgorithm: .fusion,
        sensitivity: .medium,
        bannerNotificationsEnabled: false,
        notificationSoundEnabled: false,
        launchAtLogin: false
    )

    private enum CodingKeys: String, CodingKey {
        case storedCheckIntervalSeconds
        case postureAlgorithm
        case sensitivity
        case bannerNotificationsEnabled
        case notificationSoundEnabled
        case launchAtLogin
        case debugEnabled
        case baseline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storedCheckIntervalSeconds = Self.clampInterval(try container.decode(Int.self, forKey: .storedCheckIntervalSeconds))
        // 구버전 저장값(algorithm1/algorithm2 등 사라진 케이스)은 디코드 실패할 수 있으므로 try?로 흡수하고 기본값으로 마이그레이션.
        postureAlgorithm = (try? container.decodeIfPresent(PostureAlgorithmID.self, forKey: .postureAlgorithm)) ?? .fusion
        sensitivity = try container.decode(Sensitivity.self, forKey: .sensitivity)
        bannerNotificationsEnabled = try container.decode(Bool.self, forKey: .bannerNotificationsEnabled)
        notificationSoundEnabled = try container.decode(Bool.self, forKey: .notificationSoundEnabled)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        debugEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .debugEnabled)) ?? false
        baseline = try container.decodeIfPresent(Baseline.self, forKey: .baseline)
        // 구버전에 있던 cameraPlacement 키는 더 이상 사용하지 않으며, 존재해도 디코딩에서 무시된다.
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(checkIntervalSeconds, forKey: .storedCheckIntervalSeconds)
        try container.encode(postureAlgorithm, forKey: .postureAlgorithm)
        try container.encode(sensitivity, forKey: .sensitivity)
        try container.encode(bannerNotificationsEnabled, forKey: .bannerNotificationsEnabled)
        try container.encode(notificationSoundEnabled, forKey: .notificationSoundEnabled)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(debugEnabled, forKey: .debugEnabled)
        try container.encodeIfPresent(baseline, forKey: .baseline)
    }

    private static func clampInterval(_ value: Int) -> Int {
        min(180, max(10, value))
    }
}
