import AppKit
import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var postureState: PostureState = .noEval
    @Published public private(set) var statusText = "추적 준비 중"
    @Published public private(set) var isPaused = false
    @Published public private(set) var nextCheckDescription = "다음 점검 대기"
    @Published public private(set) var diagnosticText = "측정 대기"
    @Published public private(set) var latestDiagnostic: PostureDiagnostic?
    @Published public private(set) var todayStats = DailyPostureStats(day: AppModel.todayKey())
    @Published public var settings: Settings {
        didSet {
            var persisted = settings
            if AppLaunchFlags.debugEnabled {
                // --debug 주입 값은 세션 한정이므로 저장 시 기존 영속 값으로 되돌린다.
                persisted.debugEnabled = persistedDebugEnabled
            }
            settingsStore.save(persisted)
            cameraManager.update(settings: settings)
        }
    }

    private let settingsStore = SettingsStore()
    private let persistedDebugEnabled: Bool
    private let statsStore = StatsStore()
    private let cameraManager = CameraManager()
    private var stateMachine = PostureStateMachine()
    private var notificationPolicy = NotificationPolicy()
    private let notificationManager = NotificationManager()
    private var lastStatsTimestamp = Date()
    private var countdownTimer: Timer?
    private var nextCheckDate: Date?

    public init() {
        // --debug 주입은 세션 한정: didSet 저장 시 persistedDebugEnabled로 되돌려 영속을 막는다.
        var loadedSettings = settingsStore.load()
        persistedDebugEnabled = loadedSettings.debugEnabled
        if AppLaunchFlags.debugEnabled {
            loadedSettings.debugEnabled = true
        }
        settings = loadedSettings
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
                    self.setNextCheck("카메라 점검 중")
                } else if self.isPaused {
                    self.setNextCheck("일시정지")
                } else if self.postureState == .calibrating {
                    self.setNextCheck("보정 처리 중")
                } else if self.postureState == .needsCalibration {
                    // 재보정 안내 문구를 유지한다.
                } else {
                    self.setNextCheck("측정 처리 중")
                }
            }
        }
    }

    public func start() {
        guard !isPaused else {
            return
        }
        cameraManager.start(settings: settings, baseline: settings.baseline)
        if settings.baseline == nil {
            beginCalibration()
        } else {
            statusText = "자세 추적 중"
        }
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
        stateMachine.reset(to: .paused)
        statusText = "일시정지"
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
        cameraManager.runImmediateCheck(settings: settings, baseline: settings.baseline)
    }

    public func setCheckInterval(_ interval: Double) {
        settings.checkIntervalSeconds = Int(interval.rounded())
    }

    public func setDebugEnabled(_ enabled: Bool) {
        settings.debugEnabled = enabled
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

        postureState = .calibrating
        statusText = "기준 자세 수집 중"
        setNextCheck("바른 자세를 유지해 주세요")
        // 보정 실패로 점검이 중단된 상태에서도 재보정으로 정기 점검을 재개한다.
        cameraManager.start(settings: settings, baseline: settings.baseline)
        cameraManager.runCalibration(settings: settings, baseline: settings.baseline) { [weak self] result in
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
        recordElapsedStats()
        let transition = stateMachine.apply(verdict)
        if settings.baseline == nil || verdict.requiresCalibration {
            stateMachine.reset(to: .noEval)
            postureState = .needsCalibration
            statusText = title(for: .needsCalibration)
            setNextCheck("바른 자세로 ‘재보정’을 눌러 주세요")
            cameraManager.stop()
        } else {
            postureState = transition.state
            statusText = title(for: transition.state)
        }
        if transition.state == .paused {
            isPaused = true
            setNextCheck("일시정지")
            cameraManager.stop()
        }

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
        return postureState
    }

    private func setNextCheck(_ message: String) {
        stopNextCheckCountdown()
        nextCheckDescription = message
    }

    private func startNextCheckCountdown(seconds: Int) {
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

    private func handleCalibration(_ result: CalibrationResult) -> PostureState {
        switch result {
        case .accepted(let baseline):
            settings.baseline = baseline
            postureState = .noEval
            stateMachine.reset(to: .noEval)
            statusText = "기준 자세 저장됨"
            setNextCheck("첫 자세 비교 준비 중")
        case .rejected(.unstableBaseline):
            postureState = .needsCalibration
            stateMachine.reset(to: .needsCalibration)
            statusText = "보정 실패: 자세를 유지한 뒤 다시 시도"
            setNextCheck("바른 자세로 기준자세 설정을 다시 눌러 주세요")
            cameraManager.stop()
        case .rejected(.noReliableBursts):
            postureState = .needsCalibration
            stateMachine.reset(to: .needsCalibration)
            statusText = "보정 실패: 자세 신호 부족"
            setNextCheck("카메라 구도를 확인한 뒤 다시 시도해 주세요")
            cameraManager.stop()
        }
        return postureState
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
        case .needsCalibration:
            return "바른 자세 보정 필요"
        }
    }

    /// 공통 분석 결과를 읽기만 하는 디버그 표시다. 이 값은 판정 경로에 입력되지 않는다.
    public var debugLines: [String] {
        var lines: [String] = []
        if let diagnostic = latestDiagnostic {
            let reason = diagnostic.reason.map { " — \($0)" } ?? ""
            lines.append("제품 상태  \(diagnostic.productState.rawValue)")
            lines.append("이번 버스트  \(Self.assessmentLabel(diagnostic.assessment))\(reason)")
            lines.append("증거  \(diagnostic.evidence.rawValue)")
            let summary = diagnostic.summary
            lines.append("버스트  프레임=\(summary.totalFrameCount)  유효=\(summary.validFrameCount)")
            if let feature = summary.medianFeature, let mad = summary.featureMAD {
                lines.append("feature  중앙값=\(String(format: "%.3f", feature))  MAD=\(String(format: "%.3f", mad))")
            }
            if let center = diagnostic.baselineCenter {
                let delta = diagnostic.baselineDelta.map { String(format: "%.3f", $0) } ?? "-"
                lines.append("baseline  중심=\(String(format: "%.3f", center))  delta=\(delta)")
            }
            if !summary.exclusionCounts.isEmpty {
                let exclusions = summary.exclusionCounts
                    .sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { "\($0.key.rawValue)=\($0.value)" }
                    .joined(separator: " · ")
                lines.append("제외  \(exclusions)")
            }
            for frame in diagnostic.frames.sorted(by: { $0.index < $1.index }) {
                let analysis = frame.analysis
                let feature = analysis.feature.map { String(format: "%.3f", $0) } ?? "-"
                let exclusion = analysis.exclusionReason?.rawValue ?? "none"
                lines.append("프레임 \(frame.index)  feature=\(feature)  제외=\(exclusion)")
                lines.append("landmark  \(Self.landmarkSummary(analysis.landmarks))")
                lines.append("ROI  \(Self.roiSummary(analysis.rois))")
                lines.append("depth·품질  \(Self.depthAndQualitySummary(analysis))")
            }
            if !diagnostic.stageProcessingMilliseconds.isEmpty {
                let timings = diagnostic.stageProcessingMilliseconds
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\(String(format: "%.1f", $0.value))ms" }
                    .joined(separator: " · ")
                lines.append("처리 시간  \(timings)")
            }
            if let path = diagnostic.debugArtifactPath {
                lines.append("파일  \(path)")
            } else if settings.debugEnabled {
                lines.append("파일  출력 불가 — 프로젝트 root 또는 TURTLEMECK_DEBUG_ROOT 확인")
            }
        } else {
            lines.append("아직 측정 데이터 없음 (점검 대기)")
        }
        lines.append("보정  \(Self.baselineSummary(settings.baseline))")
        lines.append("환경  주기=\(settings.checkIntervalSeconds)s")
        return lines
    }

    private static func landmarkSummary(_ landmarks: PoseLandmarks) -> String {
        [
            ("nose", landmarks.nose),
            ("leftEye", landmarks.leftEye),
            ("rightEye", landmarks.rightEye),
            ("leftEar", landmarks.leftEar),
            ("rightEar", landmarks.rightEar),
            ("neck", landmarks.neck),
            ("leftShoulder", landmarks.leftShoulder),
            ("rightShoulder", landmarks.rightShoulder)
        ].map { name, point in
            guard let point else { return "\(name)=-" }
            return "\(name)=(\(String(format: "%.2f", point.x)),\(String(format: "%.2f", point.y)),c=\(String(format: "%.2f", point.confidence)))"
        }.joined(separator: " · ")
    }

    private static func roiSummary(_ rois: PostureROIs?) -> String {
        guard let rois else { return "-" }
        func describe(_ rect: NormalizedRect) -> String {
            "(\(String(format: "%.2f", rect.x)),\(String(format: "%.2f", rect.y)),\(String(format: "%.2f", rect.width)),\(String(format: "%.2f", rect.height)))"
        }
        return "head=\(describe(rois.head)) · torso=\(describe(rois.torso)) · reference=\(describe(rois.reference))"
    }

    private static func depthAndQualitySummary(_ analysis: FrameAnalysis) -> String {
        let depth: String
        if let summary = analysis.depth {
            let range = if let minimum = summary.minimum, let maximum = summary.maximum {
                "\(String(format: "%.3f", minimum))...\(String(format: "%.3f", maximum))"
            } else {
                "-"
            }
            depth = "\(summary.width)x\(summary.height) \(summary.direction.rawValue) range=\(range)"
        } else {
            depth = "-"
        }
        let quality = analysis.quality
        return "\(depth) · confidence=\(String(format: "%.2f", quality.landmarkConfidence)) · pixels=\(String(format: "%.2f", quality.headValidPixelRatio))/\(String(format: "%.2f", quality.torsoValidPixelRatio))/\(String(format: "%.2f", quality.referenceValidPixelRatio)) · IQR=\(quality.referenceIQR.map { String(format: "%.3f", $0) } ?? "-")"
    }

    private static func assessmentLabel(_ assessment: PostureAssessment) -> String {
        switch assessment {
        case .good:
            return "정상"
        case .bad:
            return "주의(자세 흐트러짐)"
        case .noEval:
            return "판정 불가"
        }
    }

    private static func baselineSummary(_ baseline: Baseline?) -> String {
        guard let baseline else {
            return "없음(미보정)"
        }
        return "중심 \(String(format: "%.3f", baseline.center)) · 변동 \(String(format: "%.3f", baseline.dispersion)) · \(baseline.burstCount)회"
    }

    static func describe(_ diagnostic: PostureDiagnostic) -> String {
        let feature = diagnostic.summary.medianFeature.map { String(format: "%.3f", $0) } ?? "-"
        return "\(assessmentLabel(diagnostic.assessment)) · feature \(feature) · \(diagnostic.evidence.rawValue)"
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
