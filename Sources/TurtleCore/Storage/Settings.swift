import Foundation

public struct Settings: Codable, Equatable, Sendable {
    private var storedCheckIntervalSeconds: Int
    public var sensitivity: Sensitivity
    public var cameraPlacement: CameraPlacement
    public var bannerNotificationsEnabled: Bool
    public var notificationSoundEnabled: Bool
    public var launchAtLogin: Bool
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
        sensitivity: Sensitivity,
        cameraPlacement: CameraPlacement,
        bannerNotificationsEnabled: Bool,
        notificationSoundEnabled: Bool,
        launchAtLogin: Bool,
        baseline: Baseline? = nil
    ) {
        self.storedCheckIntervalSeconds = Self.clampInterval(checkIntervalSeconds)
        self.sensitivity = sensitivity
        self.cameraPlacement = cameraPlacement
        self.bannerNotificationsEnabled = bannerNotificationsEnabled
        self.notificationSoundEnabled = notificationSoundEnabled
        self.launchAtLogin = launchAtLogin
        self.baseline = baseline
    }

    public static let defaults = Settings(
        checkIntervalSeconds: 60,
        sensitivity: .medium,
        cameraPlacement: .center,
        bannerNotificationsEnabled: false,
        notificationSoundEnabled: false,
        launchAtLogin: false
    )

    private enum CodingKeys: String, CodingKey {
        case storedCheckIntervalSeconds
        case sensitivity
        case cameraPlacement
        case bannerNotificationsEnabled
        case notificationSoundEnabled
        case launchAtLogin
        case baseline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storedCheckIntervalSeconds = Self.clampInterval(try container.decode(Int.self, forKey: .storedCheckIntervalSeconds))
        sensitivity = try container.decode(Sensitivity.self, forKey: .sensitivity)
        cameraPlacement = try container.decode(CameraPlacement.self, forKey: .cameraPlacement)
        bannerNotificationsEnabled = try container.decode(Bool.self, forKey: .bannerNotificationsEnabled)
        notificationSoundEnabled = try container.decode(Bool.self, forKey: .notificationSoundEnabled)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        baseline = try container.decodeIfPresent(Baseline.self, forKey: .baseline)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(checkIntervalSeconds, forKey: .storedCheckIntervalSeconds)
        try container.encode(sensitivity, forKey: .sensitivity)
        try container.encode(cameraPlacement, forKey: .cameraPlacement)
        try container.encode(bannerNotificationsEnabled, forKey: .bannerNotificationsEnabled)
        try container.encode(notificationSoundEnabled, forKey: .notificationSoundEnabled)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encodeIfPresent(baseline, forKey: .baseline)
    }

    private static func clampInterval(_ value: Int) -> Int {
        min(180, max(10, value))
    }
}
