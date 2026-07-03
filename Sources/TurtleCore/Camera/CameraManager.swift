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
    private let relativeDepthProvider = CoreMLRelativeDepthProvider()
    private let debugCaptureStore = DebugCaptureStore()
    private let pipeline = PosturePipeline()
    private let burstProcessor = BurstProcessor()
    private var session: AVCaptureSession?
    private var settings = Settings.defaults
    private var baseline: Baseline?
    private var burstFrames: [TimedFrame] = []
    private var burstStartDate: Date?
    private var isCollectingFrames = false
    private var enqueuedFrameCount = 0
    private var lastEnqueuedCollectionTime: Double?
    private var isRunning = false
    private var scheduledWorkItem: DispatchWorkItem?
    private var calibrationCompletion: (@Sendable (CalibrationResult) -> Void)?
    private var burstRunID = 0
    private var immediateCheckPending = false
    private var routeSelector = ViewpointRouteSelector(initial: .mlAuto, hysteresis: 2)
    private var routedAlgorithm: PostureAlgorithmID = .mlAuto
    private var isPrewarmingCoreML = false

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

    static func shouldPrewarmCoreML(effectiveAlgorithm: PostureAlgorithmID, modelLoadResolved: Bool) -> Bool {
        effectiveAlgorithm.requestsCoreMLRelativeDepth && !modelLoadResolved
    }

    static func calibrationRequiredAlgorithm(for frames: [TimedFrame], fallback: PostureAlgorithmID) -> PostureAlgorithmID {
        var counts: [PostureAlgorithmID: Int] = [:]
        var order: [PostureAlgorithmID] = []
        for algorithm in frames.compactMap(\.frame.algorithm) {
            if counts[algorithm] == nil {
                order.append(algorithm)
            }
            counts[algorithm, default: 0] += 1
        }
        return order.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) } ?? fallback
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
            let debugWasEnabled = self.settings.debugEnabled
            self.settings = settings
            self.baseline = settings.baseline
            if debugWasEnabled, !settings.debugEnabled {
                self.debugCaptureStore.clearLatestRun()
            }
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
            if Self.shouldPrewarmCoreML(effectiveAlgorithm: effectiveAlgorithm(), modelLoadResolved: relativeDepthProvider.isModelLoadResolved) {
                prewarmCoreMLThenStartAuthorizedBurst()
                return
            }
            burstFrames.removeAll()
            pipeline.reset()
            let runID = nextBurstRunID()
            burstStartDate = Date()
            isCollectingFrames = true
            enqueuedFrameCount = 0
            lastEnqueuedCollectionTime = nil
            if settings.debugEnabled {
                debugCaptureStore.prepareLatestRun()
            }
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

    private func prewarmCoreMLThenStartAuthorizedBurst() {
        guard !isPrewarmingCoreML else {
            return
        }
        isPrewarmingCoreML = true
        let provider = relativeDepthProvider
        analysisQueue.async { [weak self] in
            _ = provider.prewarm()
            guard let manager = self else {
                return
            }
            manager.queue.async { [weak manager] in
                guard let manager else {
                    return
                }
                manager.isPrewarmingCoreML = false
                guard manager.shouldStartBurst else {
                    return
                }
                manager.startAuthorizedBurst()
            }
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

    /// 디버그 모드면 사용자가 고른 방식, 아니면 시점 라우팅이 고른 방식을 쓴다.
    private func effectiveAlgorithm() -> PostureAlgorithmID {
        settings.debugEnabled ? settings.postureAlgorithm : routedAlgorithm
    }

    /// 버스트 프레임들의 지배 시점 band. 알려진 band를 우선하고, 전부 미상이면 .unknown.
    private func dominantViewpointBand(of frames: [TimedFrame]) -> ViewpointBand {
        let bands = frames.compactMap { $0.frame.viewpoint?.band }
        let known = bands.filter { $0 != .unknown }
        let pool = known.isEmpty ? bands : known
        guard !pool.isEmpty else { return .unknown }
        let counts = Dictionary(grouping: pool, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key ?? .unknown
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
        lastEnqueuedCollectionTime = nil
        immediateCheckPending = false
        let calibrationAlgorithm = Self.calibrationRequiredAlgorithm(for: frames, fallback: effectiveAlgorithm())

        // 시점 분석 틱: 이번 버스트의 지배 시점으로 라우팅 방식을 갱신(히스테리시스 K=2). 자세 재보정과 별개.
        routedAlgorithm = routeSelector.update(dominantBand: dominantViewpointBand(of: frames))

        if let completion = calibrationCompletion {
            calibrationCompletion = nil
            // 보정도 동일한 2초 버스트를 사용하되, 최종 판정 대신 Calibrator로 baseline만 만든다.
            // 프레임을 실제 분석한 방식 기준으로 baseline을 요구한다. 라우팅 전환 burst에서는 새 routedAlgorithm과 프레임 신호가 다를 수 있다.
            let result = Calibrator().capture(from: frames.map(\.frame), requiredAlgorithm: calibrationAlgorithm)
            if settings.debugEnabled {
                var diagnostic = makeDiagnostic(assessment: .noEval, reason: "보정 \(calibrationLabel(result))", frames: frames)
                diagnostic.debugArtifactPath = debugCaptureStore.writeFinalAnalysis(
                    mode: "calibration",
                    verdict: nil,
                    calibrationResult: result,
                    diagnostic: diagnostic,
                    frames: frames,
                    settings: settings,
                    baseline: baseline
                )
                emitDiagnostic(diagnostic)
            }
            emitCalibration(result, completion: completion)
        } else {
            let verdict = burstProcessor.process(frames)
            var diagnostic = makeDiagnostic(assessment: verdict.assessment, frames: frames)
            if settings.debugEnabled {
                diagnostic.debugArtifactPath = debugCaptureStore.writeFinalAnalysis(
                    mode: "check",
                    verdict: verdict,
                    calibrationResult: nil,
                    diagnostic: diagnostic,
                    frames: frames,
                    settings: settings,
                    baseline: baseline
                )
            }
            emit(verdict)
            emitDiagnostic(diagnostic)
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

    private func makeDiagnostic(assessment: PostureAssessment, reason: String? = nil, frames: [TimedFrame]) -> PostureDiagnostic {
        // 신호가 있는 가장 최근 프레임을 대표로 삼아 현재 측정값을 보여준다.
        let analyzedFrames = frames.map(\.frame)
        let representative = analyzedFrames.last(where: { $0.signal != nil }) ?? analyzedFrames.last
        var observedSignalKinds: [SignalKind] = []
        for kind in analyzedFrames.compactMap({ $0.signal?.kind }) where !observedSignalKinds.contains(kind) {
            observedSignalKinds.append(kind)
        }
        return PostureDiagnostic(
            algorithm: settings.postureAlgorithm,
            assessment: assessment,
            signalKind: representative?.signal?.kind,
            value: representative?.signal?.angleDegrees,
            confidence: representative?.signal?.confidence,
            viewpoint: representative?.viewpoint?.band,
            reason: reason ?? representative?.reason,
            frameCount: analyzedFrames.count,
            validFrameCount: analyzedFrames.filter { $0.assessment != .noEval }.count,
            signalFrameCount: analyzedFrames.filter { $0.signal != nil }.count,
            observedSignalKinds: observedSignalKinds,
            debugNotes: representative?.debugNotes ?? []
        )
    }

    private func calibrationLabel(_ result: CalibrationResult) -> String {
        switch result {
        case .accepted:
            return "성공"
        case .rejected(.alreadySlouched):
            return "실패: 구부정"
        case .rejected(.noReliableFrames):
            return "실패: 신호 부족"
        }
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
            guard
                let self,
                CameraFrameQuality.isUsable(sample.sampleBuffer),
                let snapshot = self.reserveCaptureSnapshotOnQueue()
            else {
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
            enqueuedFrameCount < CameraBurstTiming.maximumAnalysisFrames,
            CameraBurstTiming.shouldSample(collectionTime: timestamp, after: lastEnqueuedCollectionTime)
        else {
            return nil
        }
        let frameIndex = enqueuedFrameCount + 1
        enqueuedFrameCount += 1
        lastEnqueuedCollectionTime = timestamp
        return CaptureSnapshot(
            runID: burstRunID,
            startDate: startDate,
            timestamp: timestamp,
            frameIndex: frameIndex,
            settings: settings,
            baseline: baseline,
            effectiveAlgorithm: effectiveAlgorithm()
        )
    }

    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, snapshot: CaptureSnapshot) {
        guard Date().timeIntervalSince(snapshot.startDate) <= CameraBurstTiming.finishDelay else {
            return
        }
        guard isBurstCurrent(snapshot.runID) else {
            return
        }

        let include3D = snapshot.effectiveAlgorithm.requests3D && SystemInfo.current.canRequestVision3D
        let inputImage = snapshot.settings.debugEnabled ? debugCaptureStore.inputImage(from: sampleBuffer) : nil
        var depthImage: CGImage?
        var landmarks = (try? detector.detect(sampleBuffer: sampleBuffer, include3D: include3D)) ?? PoseLandmarks()
        if snapshot.effectiveAlgorithm.requestsCoreMLRelativeDepth {
            if snapshot.settings.debugEnabled {
                let estimate = relativeDepthProvider.estimateWithDebugImage(
                    sampleBuffer: sampleBuffer,
                    landmarks: landmarks,
                    includeDebugImage: true
                )
                landmarks.relativeDepth = estimate?.summary
                depthImage = estimate?.debugImage
            } else {
                landmarks.relativeDepth = relativeDepthProvider.estimate(sampleBuffer: sampleBuffer, landmarks: landmarks)
            }
        }
        let processedLandmarks = landmarks
        guard Date().timeIntervalSince(snapshot.startDate) <= CameraBurstTiming.finishDelay else {
            return
        }
        if snapshot.settings.debugEnabled {
            debugCaptureStore.writeImages(index: snapshot.frameIndex, inputImage: inputImage, depthImage: depthImage)
        }

        queue.async {
            guard self.burstRunID == snapshot.runID, self.burstStartDate != nil else {
                return
            }
            let frame = self.pipeline.process(
                processedLandmarks,
                settings: snapshot.settings,
                baseline: snapshot.baseline,
                timestamp: snapshot.timestamp,
                algorithmOverride: snapshot.effectiveAlgorithm
            )
            self.burstFrames.append(TimedFrame(time: snapshot.timestamp, frame: frame, index: snapshot.frameIndex))
            if snapshot.settings.debugEnabled {
                self.debugCaptureStore.writeFrameAnalysis(index: snapshot.frameIndex, time: snapshot.timestamp, frame: frame)
            }
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
        lastEnqueuedCollectionTime = nil
        burstFrames.removeAll()
        calibrationCompletion = nil
        immediateCheckPending = false
        isPrewarmingCoreML = false
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
    let frameIndex: Int
    let settings: Settings
    let baseline: Baseline?
    let effectiveAlgorithm: PostureAlgorithmID
}

private struct SampleBufferBox: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
}

enum CameraFrameQuality {
    static func isUsable(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return false
        }
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return false
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return isUsableLumaPlane(pixelBuffer)
        case kCVPixelFormatType_32BGRA, kCVPixelFormatType_32ARGB, kCVPixelFormatType_32RGBA:
            return isUsableRGB(pixelBuffer, pixelFormat: pixelFormat)
        default:
            return true
        }
    }

    private static func isUsableLumaPlane(_ pixelBuffer: CVPixelBuffer) -> Bool {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        guard
            width > 0,
            height > 0,
            let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        else {
            return false
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        return isUsableSampleGrid(width: width, height: height) { x, y in
            let row = base.advanced(by: y * bytesPerRow)
            return Double(row.assumingMemoryBound(to: UInt8.self)[x])
        }
    }

    private static func isUsableRGB(_ pixelBuffer: CVPixelBuffer, pixelFormat: OSType) -> Bool {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard
            width > 0,
            height > 0,
            let base = CVPixelBufferGetBaseAddress(pixelBuffer)
        else {
            return false
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        return isUsableSampleGrid(width: width, height: height) { x, y in
            let row = base.advanced(by: y * bytesPerRow)
            let pixel = row.advanced(by: x * 4).assumingMemoryBound(to: UInt8.self)
            let red: UInt8
            let green: UInt8
            let blue: UInt8
            switch pixelFormat {
            case kCVPixelFormatType_32ARGB:
                red = pixel[1]
                green = pixel[2]
                blue = pixel[3]
            case kCVPixelFormatType_32RGBA:
                red = pixel[0]
                green = pixel[1]
                blue = pixel[2]
            default:
                blue = pixel[0]
                green = pixel[1]
                red = pixel[2]
            }
            return 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
        }
    }

    static func isUsableSampleGrid(width: Int, height: Int, sample: (Int, Int) -> Double) -> Bool {
        let columns = 12
        let rows = 8
        var total = 0.0
        var maximum = 0.0
        let count = columns * rows

        for row in 0..<rows {
            let y = min(height - 1, max(0, (row * height) / rows))
            for column in 0..<columns {
                let x = min(width - 1, max(0, (column * width) / columns))
                let value = sample(x, y)
                total += value
                maximum = max(maximum, value)
            }
        }

        let average = total / Double(count)
        return maximum >= 24 || average >= 8
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
    static let collectionSeconds = 3.0
    static let processingGraceSeconds = 2.0
    static let maximumAnalysisFrames = 8
    static let minimumAnalysisFrameInterval = 0.3
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

    static func shouldSample(collectionTime: Double, after previousCollectionTime: Double?) -> Bool {
        guard let previousCollectionTime else {
            return true
        }
        return collectionTime - previousCollectionTime >= minimumAnalysisFrameInterval
    }
}
