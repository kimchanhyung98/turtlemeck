import Foundation

public final class SettingsStore {
    private let defaults: UserDefaults
    private let settingsKey = "com.go.turtlemeck.settings"
    private let onboardingKey = "com.go.turtlemeck.onboardingComplete"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: onboardingKey)
    }

    public func load() -> Settings {
        guard
            let data = defaults.data(forKey: settingsKey),
            let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else {
            return .defaults
        }
        return settings
    }

    public func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: settingsKey)
    }

    public func markOnboardingComplete() {
        defaults.set(true, forKey: onboardingKey)
    }
}
