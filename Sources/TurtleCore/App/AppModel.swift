import AppKit
import AVFoundation
import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var postureState: PostureState = .noEval
    @Published public private(set) var statusText = "추적 준비 중"
    @Published public private(set) var isPaused = false
    @Published public private(set) var nextCheckDescription = "다음 점검 대기"
    @Published public private(set) var todayStats = DailyPostureStats(day: AppModel.todayKey())
    @Published public var settings: Settings {
        didSet {
            settingsStore.save(settings)
            cameraManager.update(settings: settings)
        }
    }

    public let hasCompletedOnboarding: Bool

    private let settingsStore = SettingsStore()
    private let statsStore = StatsStore()
    private let cameraManager = CameraManager()
    private var stateMachine = PostureStateMachine()
    private var notificationPolicy = NotificationPolicy()
    private let notificationManager = NotificationManager()
    private var lastStatsTimestamp = Date()

    public init() {
        settings = settingsStore.load()
        hasCompletedOnboarding = settingsStore.hasCompletedOnboarding
        todayStats = (try? statsStore.load().first { $0.day == Self.todayKey() }) ?? DailyPostureStats(day: Self.todayKey())

        cameraManager.onVerdict = { [weak self] verdict in
            Task { @MainActor in
                self?.handle(verdict)
            }
        }
        cameraManager.onNextCheckUpdate = { [weak self] seconds in
            Task { @MainActor in
                self?.nextCheckDescription = "다음 점검 \(seconds)초 후"
            }
        }
        cameraManager.onBlocked = { [weak self] reason in
            Task { @MainActor in
                self?.handleBlocked(reason: reason)
            }
        }
    }

    public func start() {
        guard !isPaused else {
            return
        }
        cameraManager.start(settings: settings, baseline: settings.baseline)
        statusText = "자세 추적 중"
    }

    public func stop() {
        recordElapsedStats()
        saveStats()
        cameraManager.stop()
    }

    public func pause() {
        recordElapsedStats()
        isPaused = true
        postureState = .paused
        statusText = "일시정지"
        saveStats()
        cameraManager.stop()
    }

    public func resume() {
        isPaused = false
        postureState = .noEval
        start()
    }

    public func checkNow() {
        guard !isPaused else {
            return
        }
        cameraManager.runImmediateCheck(settings: settings, baseline: settings.baseline)
    }

    public func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { _ in }
    }

    public func markOnboardingComplete() {
        settingsStore.markOnboardingComplete()
    }

    public func setCameraPlacement(_ placement: CameraPlacement) {
        settings.cameraPlacement = placement
    }

    public func setSensitivity(_ sensitivity: Sensitivity) {
        settings.sensitivity = sensitivity
    }

    public func setCheckInterval(_ interval: Double) {
        settings.checkIntervalSeconds = Int(interval.rounded())
    }

    public func setBannerNotifications(_ enabled: Bool) {
        settings.bannerNotificationsEnabled = enabled
        if enabled {
            notificationManager.requestAuthorization()
        }
    }

    public func setNotificationSound(_ enabled: Bool) {
        settings.notificationSoundEnabled = enabled
    }

    public func snoozeNotifications(minutes: Double = 20) {
        notificationPolicy.snooze(until: Date().addingTimeInterval(minutes * 60))
        statusText = "알림 스누즈 중"
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            settings.launchAtLogin = enabled
        } catch {
            statusText = "자동 실행 설정 실패"
        }
    }

    public func recalibrateFromCurrentGoodSignal() {
        guard !isPaused else {
            statusText = "일시정지 중"
            return
        }

        postureState = .calibrating
        statusText = "기준 자세 수집 중"
        cameraManager.runCalibration(settings: settings, baseline: settings.baseline) { [weak self] result in
            Task { @MainActor in
                self?.handleCalibration(result)
            }
        }
    }

    public func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func handle(_ verdict: BurstVerdict) {
        recordElapsedStats()
        let transition = stateMachine.apply(verdict)
        postureState = transition.state
        statusText = title(for: transition.state)

        if let alert = transition.alert {
            todayStats.record(alert)

            if settings.bannerNotificationsEnabled, notificationPolicy.shouldSend(alert: alert) {
                notificationManager.sendPostureReminder(soundEnabled: settings.notificationSoundEnabled) { [weak self] success in
                    guard success else {
                        return
                    }
                    Task { @MainActor in
                        self?.recordNotificationSent()
                    }
                }
            }
        }
        saveStats()
    }

    private func recordElapsedStats(now: Date = Date()) {
        rotateStatsIfNeeded(now: now)
        let seconds = Int(now.timeIntervalSince(lastStatsTimestamp))
        guard seconds > 0 else {
            return
        }
        todayStats.recordDuration(state: postureState, seconds: seconds)
        lastStatsTimestamp = now
    }

    private func rotateStatsIfNeeded(now: Date) {
        let day = Self.dayKey(for: now)
        guard todayStats.day != day else {
            return
        }

        saveStats()
        todayStats = (try? statsStore.load().first { $0.day == day }) ?? DailyPostureStats(day: day)
        lastStatsTimestamp = now
    }

    private func recordNotificationSent() {
        todayStats.recordNotificationSent()
        saveStats()
    }

    private func saveStats() {
        var allStats = (try? statsStore.load()) ?? []
        if let index = allStats.firstIndex(where: { $0.day == todayStats.day }) {
            allStats[index] = todayStats
        } else {
            allStats.append(todayStats)
        }
        try? statsStore.save(allStats)
    }

    private func handleCalibration(_ result: CalibrationResult) {
        switch result {
        case .accepted(let baseline):
            settings.baseline = baseline
            postureState = .noEval
            statusText = "기준 자세 저장됨"
        case .rejected(.alreadySlouched):
            postureState = .noEval
            statusText = "보정 실패: 자세를 편 뒤 다시 시도"
        case .rejected(.noReliableFrames):
            postureState = .noEval
            statusText = "보정 실패: 자세 신호 부족"
        }
    }

    private func handleBlocked(reason: String) {
        postureState = .blocked
        statusText = reason == "camera permission denied" ? "카메라 권한 필요" : "카메라 확인 필요"
    }

    private func title(for state: PostureState) -> String {
        switch state {
        case .good:
            return "자세: 정상"
        case .bad:
            return "자세: 주의"
        case .calibrating:
            return "보정 중"
        case .noEval:
            return "추적 중"
        case .paused:
            return "일시정지"
        case .blocked:
            return "카메라 확인 필요"
        }
    }

    private static func todayKey() -> String {
        dayKey(for: Date())
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
