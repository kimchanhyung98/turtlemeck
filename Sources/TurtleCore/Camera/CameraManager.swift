import AppKit
import AVFoundation
import CoreMedia
import Foundation

public final class CameraManager: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    public var onVerdict: (@Sendable (BurstVerdict) -> Void)?
    public var onNextCheckUpdate: (@Sendable (Int) -> Void)?
    public var onBlocked: (@Sendable (String) -> Void)?
    public var onDiagnostic: (@Sendable (PostureDiagnostic) -> Void)?
    public var onCaptureActivity: (@Sendable (Bool) -> Void)?

    private let queue = DispatchQueue(label: "com.go.turtlemeck.camera.control", qos: .utility)
    private let sampleBufferQueue = DispatchQueue(label: "com.go.turtlemeck.camera.samples", qos: .utility)
    private let analysisQueue = DispatchQueue(label: "com.go.turtlemeck.camera.analysis", qos: .utility)
    private let detector = PoseDetector()
    private let pipeline = PosturePipeline()
    private let burstProcessor = BurstProcessor()
    private var session: AVCaptureSession?
    private var settings = Settings.defaults
    private var baseline: Baseline?
    private var burstFrames: [TimedFrame] = []
    private var burstStartDate: Date?
    private var isCollectingFrames = false
    private var enqueuedFrameCount = 0
    private var isRunning = false
    private var scheduledWorkItem: DispatchWorkItem?
    private var calibrationCompletion: (@Sendable (CalibrationResult) -> Void)?
    private var burstRunID = 0
    private var immediateCheckPending = false

    public override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterrupted),
            name: AVCaptureSession.wasInterruptedNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    static func authorizationAction(for status: AVAuthorizationStatus) -> CameraAuthorizationAction {
        switch status {
        case .authorized:
            return .start
        case .notDetermined:
            return .requestAccess
        case .denied, .restricted:
            return .blocked("camera permission denied")
        @unknown default:
            return .blocked("camera permission denied")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func start(settings: Settings, baseline: Baseline?) {
        queue.async {
            self.settings = settings
            self.baseline = baseline
            self.isRunning = true
            self.scheduleNextBurst(after: 0)
        }
    }

    public func update(settings: Settings) {
        queue.async {
            let intervalChanged = self.settings.checkIntervalSeconds != settings.checkIntervalSeconds
            self.settings = settings
            self.baseline = settings.baseline
            // 점검 주기가 바뀌면 이미 걸린 예약을 새 주기로 다시 잡는다(추적 중 + burst/보정/즉시점검 중이 아닐 때만).
            if intervalChanged, self.isRunning, !self.isCollectingFrames,
                self.calibrationCompletion == nil, !self.immediateCheckPending {
                self.scheduleNextBurst(after: self.effectiveIntervalSeconds())
            }
        }
    }

    public func stop() {
        queue.async {
            self.isRunning = false
            self.scheduledWorkItem?.cancel()
            self.scheduledWorkItem = nil
            self.session?.stopRunning()
            self.emitCaptureActivity(false)
            self.invalidateCurrentBurst()
        }
    }

    public func runImmediateCheck(settings: Settings, baseline: Baseline?) {
        queue.async {
            self.settings = settings
            self.baseline = baseline
            // 진행 중 예약을 취소해 runCalibration과 동작을 일관화한다(직렬 큐라 안전하나 의미상 경쟁 제거 — R-4).
            self.scheduledWorkItem?.cancel()
            self.scheduledWorkItem = nil
            self.immediateCheckPending = true
            self.performBurst()
        }
    }

    public func runCalibration(settings: Settings, baseline: Baseline?, completion: @Sendable @escaping (CalibrationResult) -> Void) {
        queue.async {
            self.settings = settings
            self.baseline = baseline
            self.scheduledWorkItem?.cancel()
            self.scheduledWorkItem = nil
            self.immediateCheckPending = false
            self.calibrationCompletion = completion
            self.performBurst()
        }
    }

    private func scheduleNextBurst(after seconds: Int) {
        scheduledWorkItem?.cancel()
        guard isRunning else {
            return
        }

        let callback = onNextCheckUpdate
        DispatchQueue.main.async {
            callback?(seconds)
        }

        let item = DispatchWorkItem { [weak self] in
            self?.performBurst()
        }
        scheduledWorkItem = item
        queue.asyncAfter(deadline: .now() + .seconds(seconds), execute: item)
    }

    private func performBurst() {
        guard shouldStartBurst else {
            return
        }

        switch Self.authorizationAction(for: AVCaptureDevice.authorizationStatus(for: .video)) {
        case .start:
            startAuthorizedBurst()
        case .requestAccess:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                guard let self else {
                    return
                }
                self.queue.async {
                    guard self.shouldStartBurst else {
                        return
                    }
                    if allowed {
                        self.startAuthorizedBurst()
                    } else {
                        self.emitBlocked("camera permission denied")
                        self.calibrationCompletion = nil
                        self.immediateCheckPending = false
                        self.scheduleNextBurst(after: self.effectiveIntervalSeconds())
                    }
                }
            }
        case .blocked(let reason):
            emitBlocked(reason)
            calibrationCompletion = nil
            immediateCheckPending = false
            scheduleNextBurst(after: effectiveIntervalSeconds())
        }
    }

    private var shouldStartBurst: Bool {
        isRunning || calibrationCompletion != nil || immediateCheckPending
    }

    private func startAuthorizedBurst() {
        do {
            try configureSessionIfNeeded()
            burstFrames.removeAll()
            pipeline.reset()
            let runID = nextBurstRunID()
            burstStartDate = Date()
            isCollectingFrames = true
            enqueuedFrameCount = 0
            session?.startRunning()
            emitCaptureActivity(true)
            queue.asyncAfter(deadline: .now() + CameraBurstTiming.totalDuration) {
                self.stopCaptureForCurrentBurst(runID: runID)
            }
            queue.asyncAfter(deadline: .now() + CameraBurstTiming.finishDelay) {
                guard self.burstRunID == runID else {
                    return
                }
                self.finishBurst(runID: runID)
            }
        } catch {
            emitBlocked("camera unavailable")
            calibrationCompletion = nil
            immediateCheckPending = false
            scheduleNextBurst(after: effectiveIntervalSeconds())
        }
    }

    private func stopCaptureForCurrentBurst(runID: Int) {
        guard burstRunID == runID, isCollectingFrames else {
            return
        }
        isCollectingFrames = false
        session?.stopRunning()
        emitCaptureActivity(false)
    }

    private func finishBurst(runID: Int) {
        guard burstRunID == runID else {
            return
        }
        session?.stopRunning()
        emitCaptureActivity(false)
        isCollectingFrames = false
        let frames = burstFrames
        burstStartDate = nil
        enqueuedFrameCount = 0
        immediateCheckPending = false

        if let completion = calibrationCompletion {
            calibrationCompletion = nil
            // 보정도 동일한 2초 버스트를 사용하되, 최종 판정 대신 Calibrator로 baseline만 만든다.
            let result = Calibrator().capture(from: frames.map(\.frame))
            emitCalibration(result, completion: completion)
        } else {
            let verdict = burstProcessor.process(frames)
            emit(verdict)
            emitDiagnostic(makeDiagnostic(verdict: verdict, frames: frames))
        }
        burstFrames.removeAll()

        if isRunning {
            scheduleNextBurst(after: effectiveIntervalSeconds())
        }
    }

    private func emit(_ verdict: BurstVerdict) {
        let callback = onVerdict
        DispatchQueue.main.async {
            callback?(verdict)
        }
    }

    private func makeDiagnostic(verdict: BurstVerdict, frames: [TimedFrame]) -> PostureDiagnostic {
        // 신호가 있는 가장 최근 프레임을 대표로 삼아 현재 측정값을 보여준다.
        let representative = frames.last(where: { $0.frame.signal != nil })?.frame ?? frames.last?.frame
        return PostureDiagnostic(
            algorithm: settings.postureAlgorithm,
            assessment: verdict.assessment,
            signalKind: representative?.signal?.kind,
            value: representative?.signal?.angleDegrees,
            confidence: representative?.signal?.confidence,
            viewpoint: representative?.viewpoint?.band,
            reason: representative?.reason
        )
    }

    private func emitDiagnostic(_ diagnostic: PostureDiagnostic) {
        let callback = onDiagnostic
        DispatchQueue.main.async {
            callback?(diagnostic)
        }
    }

    private func emitCaptureActivity(_ active: Bool) {
        let callback = onCaptureActivity
        DispatchQueue.main.async {
            callback?(active)
        }
    }

    private func emitCalibration(_ result: CalibrationResult, completion: @Sendable @escaping (CalibrationResult) -> Void) {
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private func emitBlocked(_ reason: String) {
        let callback = onBlocked
        DispatchQueue.main.async {
            callback?(reason)
        }
    }

    private func effectiveIntervalSeconds() -> Int {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return min(180, max(120, settings.checkIntervalSeconds * 2))
        }
        return settings.checkIntervalSeconds
    }

    private func configureSessionIfNeeded() throws {
        guard session == nil else {
            return
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )

        guard let device = discovery.devices.first else {
            throw CameraError.noCamera
        }

        try device.lockForConfiguration()
        defer {
            device.unlockForConfiguration()
        }
        configureFrameRate(for: device)

        let session = AVCaptureSession()
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }
        session.sessionPreset = .vga640x480

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sampleBufferQueue)
        guard session.canAddOutput(output) else {
            throw CameraError.cannotAddOutput
        }
        session.addOutput(output)

        self.session = session
    }

    private func configureFrameRate(for device: AVCaptureDevice) {
        let desiredFrameRate = 5.0
        let desiredDuration = CMTime(value: 1, timescale: 5)
        let ranges = device.activeFormat.videoSupportedFrameRateRanges

        let duration: CMTime
        if ranges.contains(where: { $0.minFrameRate <= desiredFrameRate && desiredFrameRate <= $0.maxFrameRate }) {
            duration = desiredDuration
        } else if let slowestRange = ranges.max(by: { CMTimeCompare($0.maxFrameDuration, $1.maxFrameDuration) < 0 }) {
            duration = slowestRange.maxFrameDuration
        } else {
            return
        }

        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let sample = SampleBufferBox(sampleBuffer: sampleBuffer)
        queue.async { [weak self] in
            guard let self, let snapshot = self.reserveCaptureSnapshotOnQueue() else {
                return
            }
            self.analysisQueue.async { [weak self] in
                self?.processSampleBuffer(sample.sampleBuffer, snapshot: snapshot)
            }
        }
    }

    private func reserveCaptureSnapshotOnQueue() -> CaptureSnapshot? {
        let now = Date()
        guard
            isCollectingFrames,
            let startDate = burstStartDate,
            let timestamp = CameraBurstTiming.collectionTime(elapsed: now.timeIntervalSince(startDate)),
            enqueuedFrameCount < CameraBurstTiming.maximumAnalysisFrames
        else {
            return nil
        }
        enqueuedFrameCount += 1
        return CaptureSnapshot(
            runID: burstRunID,
            startDate: startDate,
            timestamp: timestamp,
            settings: settings,
            baseline: baseline
        )
    }

    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, snapshot: CaptureSnapshot) {
        guard Date().timeIntervalSince(snapshot.startDate) <= CameraBurstTiming.finishDelay else {
            return
        }
        guard isBurstCurrent(snapshot.runID) else {
            return
        }

        let include3D = snapshot.settings.postureAlgorithm.requests3D && SystemInfo.current.canRequestVision3D
        let landmarks = (try? detector.detect(sampleBuffer: sampleBuffer, include3D: include3D)) ?? PoseLandmarks()
        guard Date().timeIntervalSince(snapshot.startDate) <= CameraBurstTiming.finishDelay else {
            return
        }

        queue.async {
            guard self.burstRunID == snapshot.runID, self.burstStartDate != nil else {
                return
            }
            let frame = self.pipeline.process(
                landmarks,
                settings: snapshot.settings,
                baseline: snapshot.baseline,
                timestamp: snapshot.timestamp
            )
            self.burstFrames.append(TimedFrame(time: snapshot.timestamp, frame: frame))
        }
    }

    private func isBurstCurrent(_ runID: Int) -> Bool {
        queue.sync {
            burstRunID == runID && burstStartDate != nil
        }
    }

    private func nextBurstRunID() -> Int {
        burstRunID += 1
        return burstRunID
    }

    private func invalidateCurrentBurst() {
        burstRunID += 1
        burstStartDate = nil
        isCollectingFrames = false
        enqueuedFrameCount = 0
        burstFrames.removeAll()
        calibrationCompletion = nil
        immediateCheckPending = false
    }

    @objc private func sessionInterrupted() {
        queue.async {
            self.session?.stopRunning()
            self.emitCaptureActivity(false)
            self.invalidateCurrentBurst()
            self.emit(BurstVerdict(assessment: .noEval))
            if self.isRunning {
                self.scheduleNextBurst(after: self.effectiveIntervalSeconds())
            }
        }
    }

    @objc private func screensDidSleep() {
        queue.async {
            self.session?.stopRunning()
            self.emitCaptureActivity(false)
            self.invalidateCurrentBurst()
        }
    }

    @objc private func screensDidWake() {
        queue.async {
            guard self.isRunning else {
                return
            }
            self.scheduleNextBurst(after: self.effectiveIntervalSeconds())
        }
    }
}

private struct CaptureSnapshot: Sendable {
    let runID: Int
    let startDate: Date
    let timestamp: Double
    let settings: Settings
    let baseline: Baseline?
}

private struct SampleBufferBox: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
}

private enum CameraError: Error {
    case noCamera
    case cannotAddInput
    case cannotAddOutput
}

enum CameraAuthorizationAction: Equatable {
    case start
    case requestAccess
    case blocked(String)
}

enum CameraBurstTiming {
    static let warmupSeconds = 0.8
    static let collectionSeconds = 2.0
    static let processingGraceSeconds = 2.0
    static let maximumAnalysisFrames = 8
    static var totalDuration: Double {
        warmupSeconds + collectionSeconds
    }
    static var finishDelay: Double {
        totalDuration + processingGraceSeconds
    }

    static func isCollecting(elapsed: Double) -> Bool {
        elapsed >= warmupSeconds
    }

    static func collectionTime(elapsed: Double) -> Double? {
        // 수집 창[warmup, total]을 벗어난 늦은 프레임은 처리하지 않는다(3D 처리 적체로 stop이 밀려
        // 카메라가 필요 이상 켜져 있는 것을 줄임).
        guard isCollecting(elapsed: elapsed), elapsed <= totalDuration else {
            return nil
        }
        return elapsed - warmupSeconds
    }
}
