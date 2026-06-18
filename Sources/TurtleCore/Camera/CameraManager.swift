import AppKit
import AVFoundation
import CoreMedia
import Foundation

public final class CameraManager: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    public var onVerdict: (@Sendable (BurstVerdict) -> Void)?
    public var onNextCheckUpdate: (@Sendable (Int) -> Void)?
    public var onBlocked: (@Sendable (String) -> Void)?

    private let queue = DispatchQueue(label: "com.go.turtlemeck.camera", qos: .utility)
    private let detector = PoseDetector()
    private let pipeline = PosturePipeline()
    private let burstProcessor = BurstProcessor()
    private var session: AVCaptureSession?
    private var settings = Settings.defaults
    private var baseline: Baseline?
    private var burstFrames: [TimedFrame] = []
    private var burstStartDate: Date?
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
            self.settings = settings
            self.baseline = settings.baseline
        }
    }

    public func stop() {
        queue.async {
            self.isRunning = false
            self.scheduledWorkItem?.cancel()
            self.scheduledWorkItem = nil
            self.session?.stopRunning()
            self.invalidateCurrentBurst()
        }
    }

    public func runImmediateCheck(settings: Settings, baseline: Baseline?) {
        queue.async {
            self.settings = settings
            self.baseline = baseline
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
            session?.startRunning()
            queue.asyncAfter(deadline: .now() + CameraBurstTiming.totalDuration) {
                guard self.burstRunID == runID else {
                    return
                }
                self.finishBurst()
            }
        } catch {
            emitBlocked("camera unavailable")
            calibrationCompletion = nil
            immediateCheckPending = false
            scheduleNextBurst(after: effectiveIntervalSeconds())
        }
    }

    private func finishBurst() {
        session?.stopRunning()
        burstStartDate = nil
        immediateCheckPending = false

        if let completion = calibrationCompletion {
            calibrationCompletion = nil
            // 보정도 동일한 2초 버스트를 사용하되, 최종 판정 대신 Calibrator로 baseline만 만든다.
            let result = Calibrator().capture(from: burstFrames.map(\.frame))
            emitCalibration(result, completion: completion)
        } else {
            let verdict = burstProcessor.process(burstFrames)
            emit(verdict)
        }

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
        output.setSampleBufferDelegate(self, queue: queue)
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
        guard let start = burstStartDate else {
            return
        }

        let elapsed = Date().timeIntervalSince(start)
        guard let time = CameraBurstTiming.collectionTime(elapsed: elapsed) else {
            return
        }
        let landmarks = (try? detector.detect(sampleBuffer: sampleBuffer, include3D: SystemInfo.current.isAppleSilicon)) ?? PoseLandmarks()
        let frame = pipeline.process(landmarks, settings: settings, baseline: baseline, timestamp: time)
        burstFrames.append(TimedFrame(time: time, frame: frame))
    }

    private func nextBurstRunID() -> Int {
        burstRunID += 1
        return burstRunID
    }

    private func invalidateCurrentBurst() {
        burstRunID += 1
        burstStartDate = nil
        burstFrames.removeAll()
        calibrationCompletion = nil
        immediateCheckPending = false
    }

    @objc private func sessionInterrupted() {
        queue.async {
            self.session?.stopRunning()
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
    static var totalDuration: Double {
        warmupSeconds + collectionSeconds
    }

    static func isCollecting(elapsed: Double) -> Bool {
        elapsed >= warmupSeconds
    }

    static func collectionTime(elapsed: Double) -> Double? {
        guard isCollecting(elapsed: elapsed) else {
            return nil
        }
        return elapsed - warmupSeconds
    }
}
