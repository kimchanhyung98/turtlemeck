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
    @Published public private(set) var diagnosticText = "측정 대기"
    @Published public private(set) var latestDiagnostic: PostureDiagnostic?
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
                // 저전력 모드에서는 실제 주기가 설정값보다 늘어날 수 있으므로 조용히 두지 않고 명시한다(C-2).
                let suffix = ProcessInfo.processInfo.isLowPowerModeEnabled ? " · 저전력 모드" : ""
                self?.nextCheckDescription = "다음 점검 \(seconds)초 후\(suffix)"
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
                    self.nextCheckDescription = "카메라 점검 중"
                } else if self.isPaused {
                    self.nextCheckDescription = "일시정지"
                } else if self.postureState == .calibrating {
                    self.nextCheckDescription = "보정 처리 중"
                } else {
                    self.nextCheckDescription = "측정 처리 중"
                }
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
        guard !isPaused else {
            return
        }
        cameraManager.runImmediateCheck(settings: settings, baseline: settings.baseline)
    }

    public func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if granted {
                    if self.postureState == .blocked {
                        self.postureState = .noEval
                    }
                    self.statusText = "카메라 권한 허용됨"
                } else {
                    self.postureState = .blocked
                    self.statusText = "카메라 권한 필요"
                }
            }
        }
    }

    /// 최초 실행/온보딩에서 카메라를 쓸 수 있는 상태인지 확인한다(권한 + 사용 가능한 카메라 장치).
    public func checkCameraAvailability() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let hasDevice = !AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices.isEmpty
        guard hasDevice else {
            postureState = .blocked
            statusText = "사용 가능한 카메라 없음"
            return
        }
        switch status {
        case .authorized:
            if postureState == .blocked {
                postureState = .noEval
            }
            statusText = "카메라 사용 가능"
        case .notDetermined:
            statusText = "카메라 권한 요청 필요"
        case .denied, .restricted:
            postureState = .blocked
            statusText = "카메라 권한 필요"
        @unknown default:
            statusText = "카메라 상태 확인 필요"
        }
    }

    public func markOnboardingComplete() {
        settingsStore.markOnboardingComplete()
    }

    public func setSensitivity(_ sensitivity: Sensitivity) {
        settings.sensitivity = sensitivity
    }

    public func setPostureAlgorithm(_ algorithm: PostureAlgorithmID) {
        settings.postureAlgorithm = algorithm.isDebugSelectableMethod ? algorithm : .mlAuto
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

    private func handle(_ verdict: BurstVerdict) {
        recordElapsedStats()
        let transition = stateMachine.apply(verdict)
        postureState = transition.state
        statusText = title(for: transition.state)
        if transition.state == .paused {
            isPaused = true
            nextCheckDescription = "일시정지"
            cameraManager.stop()
        } else if transition.state == .needsCalibration {
            // 추적이 지속 실패했다 — 조용히 멈추지 않고 기준자세 보정을 요청한다(개인화로 카메라 시점/방향에 맞춤).
            nextCheckDescription = "바른 자세로 ‘재보정’을 눌러 주세요"
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
            stateMachine.reset(to: .noEval)
            statusText = "기준 자세 저장됨"
        case .rejected(.alreadySlouched):
            postureState = .noEval
            stateMachine.reset(to: .noEval)
            statusText = "보정 실패: 자세를 편 뒤 다시 시도"
        case .rejected(.noReliableFrames):
            postureState = .noEval
            stateMachine.reset(to: .noEval)
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
        case .needsCalibration:
            return "바른 자세 보정 필요"
        }
    }

    /// 디버그 패널용 상세 측정 라인. 시점·신호·3D 사용여부·보정상태·환경을 한눈에 보여준다.
    public var debugLines: [String] {
        var lines: [String] = []
        if let diagnostic = latestDiagnostic {
            lines.append("AI/ML 방식  \(diagnostic.algorithm.title)")
            let reason = diagnostic.reason.map { " — \($0)" } ?? ""
            lines.append("판정  \(Self.assessmentLabel(diagnostic.assessment))\(reason)")
            lines.append("시점  \(diagnostic.viewpoint.map(Self.viewpointLabel) ?? "?")")
            if let kind = diagnostic.signalKind {
                let value = diagnostic.value.map { String(format: "%.1f", $0) } ?? "-"
                let confidence = diagnostic.confidence.map { String(format: "%.2f", $0) } ?? "-"
                lines.append("신호  \(kind.label)=\(value)  신뢰=\(confidence)")
            } else {
                lines.append("신호  없음")
            }
            lines.append("버스트  프레임=\(diagnostic.frameCount)  유효=\(diagnostic.validFrameCount)  신호=\(diagnostic.signalFrameCount)")
            if !diagnostic.observedSignalKinds.isEmpty {
                lines.append("관측  \(diagnostic.observedSignalKinds.map(\.label).joined(separator: " · "))")
            }
            lines.append(contentsOf: diagnostic.debugNotes)
            if let path = diagnostic.debugArtifactPath {
                lines.append("파일  \(path)")
            }
        } else {
            lines.append("아직 측정 데이터 없음 (점검 대기)")
        }
        if let warning = Self.mlBaselineWarning(settings.postureAlgorithm, baseline: settings.baseline) {
            lines.append("주의  \(warning)")
        }
        lines.append(Self.mlRequestSummary(settings.postureAlgorithm))
        lines.append("보정  \(Self.baselineSummary(settings.baseline))")
        lines.append("환경  주기=\(settings.checkIntervalSeconds)s  민감도=\(settings.sensitivity.title)")
        return lines
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
        var parts: [String] = []
        if let value = baseline.profileAngle { parts.append("측면 \(String(format: "%.0f", value))°") }
        if let value = baseline.threeQuarterAngle { parts.append("3-4 \(String(format: "%.0f", value))°") }
        if let value = baseline.frontHeadDropRatio { parts.append("정면 \(String(format: "%.2f", value))") }
        if let value = baseline.bodyFrameAngle { parts.append("3D축 \(String(format: "%.0f", value))°") }
        if let value = baseline.depthDeltaNorm { parts.append("3D깊이 \(String(format: "%.2f", value))") }
        if let value = baseline.relativeDepthDelta { parts.append("상대깊이 \(String(format: "%.2f", value))") }
        if let value = baseline.frontFaceBottomY { parts.append("얼굴 \(String(format: "%.2f", value))") }
        return parts.isEmpty ? "없음(미보정)" : parts.joined(separator: " · ")
    }

    private static func mlRequestSummary(_ algorithm: PostureAlgorithmID) -> String {
        let coreML = algorithm.requestsCoreMLRelativeDepth ? "요청" : "미요청"
        let vision3D: String
        if algorithm.requests3D {
            vision3D = SystemInfo.current.canRequestVision3D ? "요청" : "차단"
        } else {
            vision3D = "미요청"
        }
        return "요청  CoreML=\(coreML)  Vision3D=\(vision3D)"
    }

    private static func mlBaselineWarning(_ algorithm: PostureAlgorithmID, baseline: Baseline?) -> String? {
        guard let baseline else {
            return algorithm.isUserSelectableMLMethod ? "ML 기준 없음(재보정 필요)" : nil
        }
        switch algorithm {
        case .mlAuto:
            let hasMLBaseline = baseline.relativeDepthDelta != nil || baseline.depthDeltaNorm != nil || baseline.bodyFrameAngle != nil
            return hasMLBaseline ? nil : "ML 기준 없음(재보정 필요)"
        case .coreMLRelativeDepth:
            return baseline.relativeDepthDelta == nil ? "Core ML 기준 없음(재보정 필요)" : nil
        case .depthDelta:
            return baseline.depthDeltaNorm == nil ? "3D깊이 기준 없음(재보정 필요)" : nil
        case .bodyFrame3D:
            return baseline.bodyFrameAngle == nil ? "3D축 기준 없음(재보정 필요)" : nil
        case .profileGeometry, .frontProxy, .fusion:
            return nil
        }
    }

    static func describe(_ diagnostic: PostureDiagnostic) -> String {
        guard let kind = diagnostic.signalKind else {
            return diagnostic.reason ?? "측정 신호 없음"
        }
        let value = diagnostic.value.map { String(format: "%.1f", $0) } ?? "-"
        let confidence = diagnostic.confidence.map { String(format: "%.2f", $0) } ?? "-"
        let viewpoint = diagnostic.viewpoint.map(Self.viewpointLabel) ?? "?"
        return "[\(diagnostic.algorithm.title)] \(kind.label) \(value) · 신뢰 \(confidence) · \(viewpoint)"
    }

    private static func viewpointLabel(_ band: ViewpointBand) -> String {
        switch band {
        case .front:
            return "정면"
        case .profileLeft:
            return "좌측면"
        case .profileRight:
            return "우측면"
        case .threeQuarterLeft:
            return "좌3-4"
        case .threeQuarterRight:
            return "우3-4"
        case .unknown:
            return "시점 미상"
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
