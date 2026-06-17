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

    private static func clampInterval(_ value: Int) -> Int {
        min(180, max(10, value))
    }
}
