import AppKit
import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var postureState: PostureState = .noEval
    @Published public private(set) var statusText = "점검 준비 중"
    @Published public private(set) var isPaused = false
    @Published public private(set) var nextCheckDescription = "다음 점검 대기"
    @Published public private(set) var diagnosticText = "측정 대기"
    @Published public private(set) var latestDiagnostic: PostureDiagnostic?
    @Published public private(set) var todayStats = DailyPostureStats(day: AppModel.todayKey())
    @Published public var settings: Settings {
        didSet {
            var persisted = settings
            // 실행 인자로 정한 `debugEnabled`만 UserDefaults에 저장하지 않는다.
            persisted.debugEnabled = false
            settingsStore.save(persisted)
            cameraManager.update(settings: settings)
        }
    }

    private let settingsStore = SettingsStore()
    private let statsStore = StatsStore()
    private let cameraManager = CameraManager()
    private var stateMachine = PostureStateMachine()
    private var notificationPolicy = NotificationPolicy()
    private let notificationManager = NotificationManager()
    private var lastStatsTimestamp = Date()
    private var countdownTimer: Timer?
    private var statsRolloverTimer: Timer?
    private var statsClockObservers: [NSObjectProtocol] = []
    private var statsCalendar = DailyStatsTimeline.localGregorianCalendar()
    private var nextCheckDate: Date?
    private var isRunning = false

    public init() {
        var loadedSettings = settingsStore.load()
        loadedSettings.launchAtLogin = LaunchAtLogin.isEnabled
        loadedSettings.debugEnabled = AppLaunchFlags.debugEnabled
        settings = loadedSettings
        var persistedSettings = loadedSettings
        persistedSettings.debugEnabled = false
        settingsStore.save(persistedSettings)
        todayStats = (try? statsStore.load().first { $0.day == Self.todayKey() }) ?? DailyPostureStats(day: Self.todayKey())

        cameraManager.onVerdict = { [weak self] verdict in
            self?.handle(verdict) ?? .noEval
        }
        cameraManager.onNextCheckUpdate = { [weak self] seconds in
            Task { @MainActor in
                self?.startNextCheckCountdown(seconds: seconds)
            }
        }
        cameraManager.onBlocked = { [weak self] reason in
            Task { @MainActor in
                self?.handleBlocked(reason: reason)
            }
        }
        cameraManager.onDiagnostic = { [weak self] diagnostic in
            Task { @MainActor in
                self?.diagnosticText = AppModel.describe(diagnostic)
                self?.latestDiagnostic = diagnostic
            }
        }
        cameraManager.onCaptureActivity = { [weak self] active in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if active {
                    self.setNextCheck("카메라로 점검 중")
                } else if self.isPaused {
                    self.setNextCheck("중지됨")
                } else if self.postureState == .calibrating {
                    self.setNextCheck("보정 분석 중")
                } else if self.postureState == .needsCalibration || self.postureState == .blocked {
                    // 재보정·카메라 안내는 덮어쓰지 않는다.
                } else {
                    self.setNextCheck("점검 분석 중")
                }
            }
        }
    }

    public func start() {
        guard !isPaused else {
            return
        }
        isRunning = true
        startStatsClockObservation()
        scheduleStatsRollover()
        cameraManager.start(settings: settings)
        if settings.baseline == nil {
            beginCalibration()
        } else {
            statusText = "자세 점검 중"
        }
    }

    public func stop() {
        recordElapsedStats()
        saveStats()
        isRunning = false
        statsRolloverTimer?.invalidate()
        statsRolloverTimer = nil
        stopStatsClockObservation()
        cameraManager.stop()
    }

    public func pause() {
        recordElapsedStats()
        isPaused = true
        postureState = .paused
        stateMachine.reset(to: .paused)
        statusText = "중지됨"
        saveStats()
        cameraManager.stop()
    }

    public func resume() {
        isPaused = false
        postureState = .noEval
        stateMachine.reset(to: .noEval)
        start()
    }

    public func checkNow() {
        guard !isPaused, postureState != .needsCalibration, settings.baseline != nil else {
            return
        }
        cameraManager.runImmediateCheck(settings: settings)
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
        beginCalibration()
    }

    private func beginCalibration() {
        guard !isPaused else {
            statusText = "일시정지 중"
            return
        }
        guard postureState != .calibrating else { return }

        recordElapsedStats()
        postureState = .calibrating
        statusText = "기준 자세 보정 중"
        setNextCheck("바른 자세를 유지해 주세요")
        // 보정 실패로 멈춘 정기 점검도 재보정과 함께 다시 시작한다.
        cameraManager.start(settings: settings)
        cameraManager.runCalibration(settings: settings) { [weak self] result in
            self?.handleCalibration(result) ?? .noEval
        }
    }

    public func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    public var debugArtifactPath: String? {
        latestDiagnostic?.debugArtifactPath
    }

    public func openDebugArtifacts() {
        guard let path = debugArtifactPath else {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    public func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func handle(_ verdict: BurstVerdict) -> PostureState {
        guard !isPaused, postureState != .calibrating else {
            return postureState
        }
        recordElapsedStats()
        let transition = stateMachine.apply(verdict)
        if settings.baseline == nil || verdict.requiresCalibration {
            stateMachine.reset(to: .noEval)
            postureState = .needsCalibration
            statusText = title(for: .needsCalibration)
            setNextCheck("바른 자세로 ‘보정’을 눌러 주세요")
            cameraManager.stop()
        } else {
            postureState = transition.state
            statusText = title(for: transition.state)
        }
        if transition.state == .paused {
            isPaused = true
            setNextCheck("중지됨")
            cameraManager.stop()
        }

        if let alert = transition.alert {
            todayStats.record(alert)

            if settings.bannerNotificationsEnabled || settings.notificationSoundEnabled,
               notificationPolicy.shouldSend(alert: alert) {
                notificationManager.sendPostureReminder(
                    bannerEnabled: settings.bannerNotificationsEnabled,
                    soundEnabled: settings.notificationSoundEnabled
                ) { [weak self] success in
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
        return postureState
    }

    private func setNextCheck(_ message: String) {
        stopNextCheckCountdown()
        nextCheckDescription = message
    }

    private func startNextCheckCountdown(seconds: Int) {
        guard !isPaused, postureState != .calibrating else { return }
        stopNextCheckCountdown()
        nextCheckDate = Date().addingTimeInterval(Double(seconds))
        updateNextCheckCountdown()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateNextCheckCountdown()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func updateNextCheckCountdown() {
        guard let nextCheckDate else { return }
        let remaining = max(0, Int(nextCheckDate.timeIntervalSinceNow.rounded(.up)))
        nextCheckDescription = "다음 점검 \(remaining)초 후"
        if remaining == 0 {
            stopNextCheckCountdown()
        }
    }

    private func stopNextCheckCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        nextCheckDate = nil
    }

    private func recordElapsedStats(now: Date = Date()) {
        if now < lastStatsTimestamp {
            lastStatsTimestamp = now
        }
        let calendar = statsCalendar
        let segments = DailyStatsTimeline.segments(from: lastStatsTimestamp, to: now, calendar: calendar)
        for segment in segments {
            switchStats(to: segment.day)
            todayStats.recordDuration(state: postureState, seconds: segment.seconds)
        }
        switchStats(to: DailyStatsTimeline.dayKey(for: now, calendar: calendar))
        guard !segments.isEmpty else {
            return
        }
        // 적립한 정수 초만큼만 전진시켜 1초 미만 잔여분을 다음 기록으로 이월한다.
        let allocatedSeconds = segments.reduce(0) { $0 + $1.seconds }
        lastStatsTimestamp = lastStatsTimestamp.addingTimeInterval(TimeInterval(allocatedSeconds))
    }

    private func switchStats(to day: String) {
        guard todayStats.day != day else {
            return
        }

        saveStats()
        todayStats = (try? statsStore.load().first { $0.day == day }) ?? DailyPostureStats(day: day)
    }

    private func scheduleStatsRollover(now: Date = Date()) {
        guard isRunning else {
            return
        }
        statsRolloverTimer?.invalidate()
        let calendar = statsCalendar
        let startOfDay = calendar.startOfDay(for: now)
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            statsRolloverTimer = nil
            return
        }
        let timer = Timer(timeInterval: max(0.1, nextMidnight.timeIntervalSince(now)), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else {
                    return
                }
                self.recordElapsedStats()
                self.scheduleStatsRollover()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statsRolloverTimer = timer
    }

    private func startStatsClockObservation() {
        guard statsClockObservers.isEmpty else {
            return
        }
        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemTimeZoneDidChange, Notification.Name.NSSystemClockDidChange] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isRunning else {
                        return
                    }
                    let now = Date()
                    if name == Notification.Name.NSSystemTimeZoneDidChange {
                        self.recordElapsedStats(now: now)
                    }
                    self.lastStatsTimestamp = now
                    self.statsCalendar = DailyStatsTimeline.localGregorianCalendar()
                    self.switchStats(to: DailyStatsTimeline.dayKey(for: now, calendar: self.statsCalendar))
                    self.scheduleStatsRollover(now: now)
                }
            }
            statsClockObservers.append(observer)
        }
    }

    private func stopStatsClockObservation() {
        let center = NotificationCenter.default
        for observer in statsClockObservers {
            center.removeObserver(observer)
        }
        statsClockObservers.removeAll()
    }

    private func recordNotificationSent() {
        todayStats.recordNotificationSent()
        saveStats()
    }

    private func saveStats() {
        try? statsStore.save(todayStats)
    }

    private func handleCalibration(_ result: CalibrationResult) -> PostureState {
        guard !isPaused, postureState == .calibrating else {
            return postureState
        }
        switch result {
        case .accepted(let baseline):
            settings.baseline = baseline
            postureState = .noEval
            stateMachine.reset(to: .noEval)
            statusText = "기준 자세 저장됨"
            setNextCheck("첫 점검 준비 중")
        case .rejected(.unstableBaseline):
            postureState = .needsCalibration
            stateMachine.reset(to: .needsCalibration)
            statusText = "보정 실패: 자세를 유지한 뒤 다시 시도"
            setNextCheck(Self.calibrationGuidance(for: .unstableBaseline))
            cameraManager.stop()
        case .rejected(.cameraPermissionDenied):
            postureState = .blocked
            stateMachine.reset(to: .blocked)
            statusText = "카메라 권한 필요"
            setNextCheck(Self.calibrationGuidance(for: .cameraPermissionDenied))
            cameraManager.stop()
        case .rejected(.cameraUnavailable):
            postureState = .blocked
            stateMachine.reset(to: .blocked)
            statusText = "카메라 사용 불가"
            setNextCheck(Self.calibrationGuidance(for: .cameraUnavailable))
            cameraManager.stop()
        case .rejected(.noReliableBursts):
            postureState = .needsCalibration
            stateMachine.reset(to: .needsCalibration)
            statusText = "보정 실패: 자세 신호 부족"
            setNextCheck(Self.calibrationGuidance(for: .noReliableBursts))
            cameraManager.stop()
        case .rejected(.postureUnassessable):
            postureState = .needsCalibration
            stateMachine.reset(to: .needsCalibration)
            statusText = "보정 실패: 자세를 확인할 수 없음"
            setNextCheck(Self.calibrationGuidance(for: .postureUnassessable))
            cameraManager.stop()
        }
        return postureState
    }

    public nonisolated static func calibrationGuidance(for reason: CalibrationRejectReason) -> String {
        switch reason {
        case .unstableBaseline:
            "바른 자세로 ‘보정’을 눌러 주세요"
        case .cameraPermissionDenied:
            "카메라 권한을 허용한 뒤 ‘보정’을 눌러 주세요"
        case .cameraUnavailable:
            "카메라를 사용할 수 있는 상태로 만든 뒤 ‘보정’을 눌러 주세요"
        case .noReliableBursts:
            "카메라 구도를 확인한 뒤 ‘보정’을 눌러 주세요"
        case .postureUnassessable:
            "바른 자세로 ‘보정’을 눌러 주세요"
        }
    }

    private func handleBlocked(reason: CameraBlockReason) {
        guard !isPaused, postureState != .calibrating else { return }
        recordElapsedStats()
        postureState = .blocked
        stateMachine.reset(to: .blocked)
        switch reason {
        case .permissionDenied:
            statusText = "카메라 권한 필요"
            setNextCheck("카메라 권한을 허용해 주세요")
        case .unavailable:
            statusText = "카메라 사용 불가"
            setNextCheck("카메라를 사용할 수 있는 상태인지 확인해 주세요")
        }
    }

    private func title(for state: PostureState) -> String {
        switch state {
        case .good:
            return "자세: 정상"
        case .bad:
            return "자세: 주의"
        case .calibrating:
            return "기준 자세 보정 중"
        case .noEval:
            return "자세 점검 중"
        case .paused:
            return "중지됨"
        case .blocked:
            return "카메라 확인 필요"
        case .needsCalibration:
            return "보정 필요"
        }
    }

    private static func todayKey() -> String {
        dayKey(for: Date())
    }

    private static func dayKey(for date: Date) -> String {
        DailyStatsTimeline.dayKey(for: date)
    }
}
