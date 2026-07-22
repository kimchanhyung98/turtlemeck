import AppKit
import AVFoundation
import CoreMedia
import Foundation

public final class CameraManager: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    public var onVerdict: (@MainActor @Sendable (BurstVerdict) -> PostureState)?
    public var onNextCheckUpdate: (@Sendable (Int) -> Void)?
    public var onBlocked: (@Sendable (CameraBlockReason) -> Void)?
    public var onDiagnostic: (@Sendable (PostureDiagnostic) -> Void)?
    public var onCaptureActivity: (@Sendable (Bool) -> Void)?

    private let queue = DispatchQueue(label: "com.go.turtlemeck.camera.control", qos: .utility)
    private let sampleBufferQueue = DispatchQueue(label: "com.go.turtlemeck.camera.samples", qos: .utility)
    private let analysisQueue = DispatchQueue(label: "com.go.turtlemeck.camera.analysis", qos: .utility)
    private let outputQueue = DispatchQueue(label: "com.go.turtlemeck.debug-output", qos: .utility)
    private let localAnalysisQueue = DispatchQueue(label: "com.go.turtlemeck.local-analysis", qos: .utility)
    private let detector = PoseDetector()
    private let depthProvider = CoreMLRelativeDepthProvider()
    private let frameAnalyzer = PostureFrameAnalyzer()
    private let burstProcessor = BurstProcessor()
    private let debugStore = DebugCaptureStore()
    private let localAnalysisRunner = LocalAIAnalysisRunner()

    private var session: AVCaptureSession?
    private var captureConfiguration: CaptureConfiguration?
    private var settings = Settings.defaults
    private var frames: [TimedFrame] = []
    private var pendingFrameOutputs: [PendingFrameOutput] = []
    private var subjectSelector = UpperBodySubjectSelector()
    private var burstStartDate: Date?
    private var isCollectingFrames = false
    private var enqueuedFrameCount = 0
    private var lastEnqueuedCollectionTime: Double?
    private var currentDebugSession: DebugCaptureSession?
    private var isRunning = false
    private var scheduledWorkItem: DispatchWorkItem?
    private var calibrationCompletion: (@MainActor @Sendable (CalibrationResult) -> PostureState)?
    private var calibrationSummaries: [BurstSummary] = []
    private var calibrationAttempts = 0
    private var burstRunID = 0
    private var immediateCheckPending = false
    private var isPrewarmingModel = false

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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public static func authorizationAction(for status: AVAuthorizationStatus) -> CameraAuthorizationAction {
        switch status {
        case .authorized: .start
        case .notDetermined: .requestAccess
        case .denied, .restricted: .blocked(.permissionDenied)
        @unknown default: .blocked(.permissionDenied)
        }
    }

    public static func burstCompletionAction(receivedFrameCount: Int) -> CameraBurstCompletionAction {
        receivedFrameCount == 0 ? .blocked(.unavailable) : .process
    }

    public func start(settings: Settings) {
        queue.async {
            self.settings = settings
            self.isRunning = true
            self.scheduleNextBurst(after: 0)
        }
    }

    public func update(settings: Settings) {
        queue.async {
            let intervalChanged = self.settings.checkIntervalSeconds != settings.checkIntervalSeconds
            self.settings = settings
            if intervalChanged, self.isRunning, self.burstStartDate == nil, self.calibrationCompletion == nil {
                self.scheduleNextBurst(after: self.settings.checkIntervalSeconds)
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

    public func runImmediateCheck(settings: Settings) {
        queue.async {
            // 보정 중의 즉시 점검은 보정 버스트로 흡수되므로 보정이 끝날 때까지 받지 않는다.
            guard self.calibrationCompletion == nil else { return }
            self.settings = settings
            self.scheduledWorkItem?.cancel()
            self.scheduledWorkItem = nil
            if self.burstStartDate != nil {
                self.session?.stopRunning()
                self.invalidateCurrentBurst()
            }
            self.immediateCheckPending = true
            self.performBurst()
        }
    }

    public func runCalibration(
        settings: Settings,
        completion: @MainActor @Sendable @escaping (CalibrationResult) -> PostureState
    ) {
        queue.async {
            self.settings = settings
            self.scheduledWorkItem?.cancel()
            self.scheduledWorkItem = nil
            if self.burstStartDate != nil {
                self.session?.stopRunning()
                self.invalidateCurrentBurst()
            }
            self.immediateCheckPending = false
            self.calibrationSummaries.removeAll()
            self.calibrationAttempts = 0
            self.calibrationCompletion = completion
            self.performBurst()
        }
    }

    private func scheduleNextBurst(after seconds: Int) {
        scheduledWorkItem?.cancel()
        guard isRunning else { return }
        // 즉시 실행은 "다음 점검 0초 후" 안내가 무의미하므로 알리지 않는다.
        if seconds > 0 { emitNextCheck(seconds) }
        let item = DispatchWorkItem { [weak self] in self?.performBurst() }
        scheduledWorkItem = item
        queue.asyncAfter(deadline: .now() + .seconds(seconds), execute: item)
    }

    private func performBurst() {
        guard burstStartDate == nil, isRunning || calibrationCompletion != nil || immediateCheckPending else { return }
        switch Self.authorizationAction(for: AVCaptureDevice.authorizationStatus(for: .video)) {
        case .start:
            startAuthorizedBurst()
        case .requestAccess:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                guard let manager = self else { return }
                manager.queue.async {
                    if allowed { manager.startAuthorizedBurst() } else { manager.failToStart(.permissionDenied) }
                }
            }
        case .blocked(let reason):
            failToStart(reason)
        }
    }

    private func startAuthorizedBurst() {
        do {
            try configureSessionIfNeeded()
            if !depthProvider.isModelLoadResolved {
                prewarmModelThenStart()
                return
            }
            frames.removeAll()
            pendingFrameOutputs.removeAll()
            analysisQueue.async { self.subjectSelector.reset() }
            let runID = nextBurstRunID()
            currentDebugSession = settings.debugEnabled || localAnalysisRunner.isEnabled
                ? debugStore.prepareRun()
                : nil
            session?.startRunning()
            burstStartDate = Date()
            isCollectingFrames = true
            enqueuedFrameCount = 0
            lastEnqueuedCollectionTime = nil
            emitCaptureActivity(true)
            queue.asyncAfter(deadline: .now() + CameraBurstTiming.totalDuration) {
                self.stopCapture(runID: runID)
            }
            queue.asyncAfter(deadline: .now() + CameraBurstTiming.finishDelay) {
                self.finishBurst(runID: runID)
            }
        } catch {
            failToStart(.unavailable)
        }
    }

    private func prewarmModelThenStart() {
        guard !isPrewarmingModel else { return }
        isPrewarmingModel = true
        let provider = depthProvider
        analysisQueue.async { [weak self] in
            guard let manager = self else { return }
            _ = provider.prewarm()
            manager.queue.async {
                manager.isPrewarmingModel = false
                manager.startAuthorizedBurst()
            }
        }
    }

    private func stopCapture(runID: Int) {
        guard burstRunID == runID, isCollectingFrames else { return }
        isCollectingFrames = false
        session?.stopRunning()
        emitCaptureActivity(false)
    }

    private func finishBurst(runID: Int) {
        guard burstRunID == runID, let completedBurstStartDate = burstStartDate else { return }
        session?.stopRunning()
        emitCaptureActivity(false)
        isCollectingFrames = false
        let aggregationStart = Date()
        let completedFrames = frames.sorted { $0.index < $1.index }
        let completedFrameOutputs = pendingFrameOutputs.sorted { $0.index < $1.index }
        let receivedFrameCount = enqueuedFrameCount
        let summary = burstProcessor.summarize(completedFrames)
        var stageTimings = averageStageTimings(completedFrames)
        stageTimings["burstAggregation"] = Date().timeIntervalSince(aggregationStart) * 1_000
        let debugSession = currentDebugSession
        burstStartDate = nil
        enqueuedFrameCount = 0
        lastEnqueuedCollectionTime = nil
        currentDebugSession = nil
        immediateCheckPending = false
        frames.removeAll()
        pendingFrameOutputs.removeAll()

        switch Self.burstCompletionAction(receivedFrameCount: receivedFrameCount) {
        case .process:
            break
        case .blocked(let reason):
            finishBlockedBurst(
                reason,
                startedAt: completedBurstStartDate,
                summary: summary,
                frames: completedFrames,
                stageTimings: stageTimings,
                session: debugSession,
                frameOutputs: completedFrameOutputs
            )
            return
        }

        if let completion = calibrationCompletion {
            calibrationAttempts += 1
            calibrationSummaries.append(summary)
            if calibrationAttempts < CameraBurstTiming.maximumCalibrationAttempts,
               calibrationSummaries.filter(Calibrator.isReliable).count < Tuning.requiredCalibrationBursts {
                let diagnostic = calibrationDiagnostic(
                    result: nil,
                    productState: .calibrating,
                    summary: summary,
                    frames: completedFrames,
                    stageTimings: stageTimings
                )
                deliverDiagnostic(
                    diagnostic,
                    session: debugSession,
                    verdict: nil,
                    calibrationResult: nil,
                    baseline: settings.baseline,
                    frameOutputs: completedFrameOutputs,
                    afterOutput: {
                        self.queue.asyncAfter(deadline: .now() + CameraBurstTiming.calibrationRetryDelaySeconds) {
                            self.performBurst()
                        }
                    }
                )
                return
            }
            calibrationCompletion = nil
            let calibrationStart = Date()
            let result = Calibrator().capture(
                from: calibrationSummaries,
                captureConfiguration: captureConfiguration
            )
            stageTimings["calibration"] = Date().timeIntervalSince(calibrationStart) * 1_000
            let stateStart = Date()
            let productState = resolveCalibration(result, completion: completion)
            stageTimings["stateTransition"] = Date().timeIntervalSince(stateStart) * 1_000
            let diagnostic = calibrationDiagnostic(
                result: result,
                productState: productState,
                summary: summary,
                frames: completedFrames,
                stageTimings: stageTimings
            )
            // 보정 실패는 수동 보정 전까지 다음 점검을 예약하지 않는다.
            let afterOutput: @Sendable () -> Void
            if case .accepted = result {
                afterOutput = { self.scheduleFollowingBurstIfNeeded(startedAt: completedBurstStartDate) }
            } else {
                afterOutput = {}
            }
            deliverDiagnostic(
                diagnostic,
                session: debugSession,
                verdict: nil,
                calibrationResult: result,
                baseline: baselineForSession(result),
                frameOutputs: completedFrameOutputs,
                afterOutput: afterOutput
            )
        } else {
            let verdictStart = Date()
            let verdict = burstProcessor.process(
                completedFrames,
                baseline: settings.baseline,
                captureConfiguration: captureConfiguration
            )
            stageTimings["baselineComparison"] = Date().timeIntervalSince(verdictStart) * 1_000
            let stateStart = Date()
            let productState = resolveVerdict(verdict)
            stageTimings["stateTransition"] = Date().timeIntervalSince(stateStart) * 1_000
            let diagnostic = PostureDiagnostic(
                assessment: verdict.assessment,
                productState: productState,
                evidence: verdict.evidence,
                summary: verdict.summary,
                baselineCenter: settings.baseline?.center,
                baselineDelta: verdict.baselineDelta,
                reason: verdict.reason,
                frames: completedFrames,
                stageProcessingMilliseconds: stageTimings
            )
            // 보정이 필요해져 점검이 중단되는 경우에는 다음 점검을 예약하지 않는다.
            let afterOutput: @Sendable () -> Void
            if productState == .needsCalibration {
                afterOutput = {}
            } else {
                afterOutput = { self.scheduleFollowingBurstIfNeeded(startedAt: completedBurstStartDate) }
            }
            deliverDiagnostic(
                diagnostic,
                session: debugSession,
                verdict: verdict,
                calibrationResult: nil,
                baseline: settings.baseline,
                frameOutputs: completedFrameOutputs,
                afterOutput: afterOutput
            )
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let sample = SampleBufferBox(sampleBuffer: sampleBuffer)
        queue.async { [weak self] in
            guard
                let self,
                let snapshot = self.reserveSnapshot()
            else { return }
            guard CameraFrameQuality.isUsable(sample.sampleBuffer) else {
                self.analysisQueue.async { [weak self] in
                    self?.processRejectedCapture(sample, snapshot: snapshot)
                }
                return
            }
            self.analysisQueue.async { [weak self] in
                self?.process(sample, snapshot: snapshot)
            }
        }
    }

    private func processRejectedCapture(_ sample: SampleBufferBox, snapshot: CaptureSnapshot) {
        guard isBurstCurrent(snapshot.runID) else { return }
        let analysis = FrameAnalysis(
            landmarks: PoseLandmarks(),
            exclusionReason: .unstableCapture,
            processingMilliseconds: ["captureQuality": 0]
        )
        queue.async {
            guard self.burstRunID == snapshot.runID, self.burstStartDate != nil else { return }
            self.frames.append(TimedFrame(time: snapshot.timestamp, analysis: analysis, index: snapshot.frameIndex))
            guard let session = snapshot.debugSession else { return }
            self.pendingFrameOutputs.append(PendingFrameOutput(
                session: session,
                index: snapshot.frameIndex,
                time: snapshot.timestamp,
                sample: sample,
                depthMap: nil,
                analysis: analysis
            ))
        }
    }

    private func reserveSnapshot() -> CaptureSnapshot? {
        let now = Date()
        guard
            isCollectingFrames,
            let startDate = burstStartDate,
            let timestamp = CameraBurstTiming.collectionTime(elapsed: now.timeIntervalSince(startDate)),
            enqueuedFrameCount < CameraBurstTiming.maximumAnalysisFrames,
            CameraBurstTiming.shouldSample(collectionTime: timestamp, after: lastEnqueuedCollectionTime)
        else { return nil }
        enqueuedFrameCount += 1
        lastEnqueuedCollectionTime = timestamp
        return CaptureSnapshot(
            runID: burstRunID,
            startDate: startDate,
            timestamp: timestamp,
            frameIndex: enqueuedFrameCount,
            debugSession: currentDebugSession
        )
    }

    private func process(_ sample: SampleBufferBox, snapshot: CaptureSnapshot) {
        guard Date().timeIntervalSince(snapshot.startDate) <= CameraBurstTiming.finishDelay, isBurstCurrent(snapshot.runID) else { return }
        let poseStart = Date()
        let poseResult = Result {
            try detector.detectCandidates(sampleBuffer: sample.sampleBuffer, orientation: .up)
        }
        let poseMilliseconds = Date().timeIntervalSince(poseStart) * 1_000
        let depthStart = Date()
        let depthMap = depthProvider.estimate(sampleBuffer: sample.sampleBuffer)
        let depthMilliseconds = Date().timeIntervalSince(depthStart) * 1_000
        var analysis: FrameAnalysis
        let featureStart: Date
        switch poseResult {
        case .failure:
            featureStart = Date()
            analysis = FrameAnalysis(
                landmarks: PoseLandmarks(),
                depth: depthMap.map(DepthSummary.init),
                exclusionReason: .modelFailure
            )
        case .success(let candidates):
            switch subjectSelector.select(from: candidates) {
            case .selected(let landmarks):
                featureStart = Date()
                analysis = frameAnalyzer.analyze(landmarks: landmarks, depthMap: depthMap)
            case .rejected(let reason):
                featureStart = Date()
                analysis = FrameAnalysis(
                    // 거부 사유 판단(머리 검출 여부)과 같은 후보를 기록해야 버스트 집계가 일관된다.
                    landmarks: candidates.first(where: { !$0.reliableHeadAnchors.isEmpty }) ?? candidates.first ?? PoseLandmarks(),
                    depth: depthMap.map(DepthSummary.init),
                    exclusionReason: reason
                )
            }
        }
        analysis.processingMilliseconds = [
            "pose2D": poseMilliseconds,
            "depthAnythingV2": depthMilliseconds,
            "feature": Date().timeIntervalSince(featureStart) * 1_000
        ]

        let completedAnalysis = analysis
        queue.async {
            guard self.burstRunID == snapshot.runID, self.burstStartDate != nil else { return }
            self.frames.append(TimedFrame(time: snapshot.timestamp, analysis: completedAnalysis, index: snapshot.frameIndex))
            guard let session = snapshot.debugSession else { return }
            self.pendingFrameOutputs.append(PendingFrameOutput(
                session: session,
                index: snapshot.frameIndex,
                time: snapshot.timestamp,
                sample: sample,
                depthMap: depthMap,
                analysis: completedAnalysis
            ))
        }
    }

    private func configureSessionIfNeeded() throws {
        guard session == nil else { return }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        guard let device = discovery.devices.first else { throw CameraError.noCamera }
        try device.lockForConfiguration()
        configureFrameRate(for: device)
        device.unlockForConfiguration()

        let session = AVCaptureSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .vga640x480
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sampleBufferQueue)
        guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        session.addOutput(output)
        // 기본 전달 포맷은 기기 의존적이라 CameraFrameQuality가 처리하는 포맷으로 고정한다.
        let preferredPixelFormats: [OSType] = [
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_32BGRA
        ]
        let availablePixelFormats = output.availableVideoPixelFormatTypes
        if let pixelFormat = preferredPixelFormats.first(where: availablePixelFormats.contains) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
        }
        self.session = session
        captureConfiguration = CaptureConfiguration(
            cameraUniqueID: device.uniqueID,
            width: 640,
            height: 480,
            orientation: "up-unmirrored"
        )
    }

    private func configureFrameRate(for device: AVCaptureDevice) {
        let desired = 5.0
        guard device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= desired && desired <= $0.maxFrameRate }) else { return }
        let duration = CMTime(value: 1, timescale: 5)
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }

    private func failToStart(_ reason: CameraBlockReason) {
        let wasCalibrating = calibrationCompletion != nil
        calibrationCompletion = nil
        calibrationSummaries.removeAll()
        calibrationAttempts = 0
        emitBlocked(reason)
        immediateCheckPending = false
        if wasCalibrating {
            isRunning = false
        } else if isRunning {
            scheduleNextBurst(after: settings.checkIntervalSeconds)
        }
    }

    private func finishBlockedBurst(
        _ reason: CameraBlockReason,
        startedAt: Date,
        summary: BurstSummary,
        frames: [TimedFrame],
        stageTimings: [String: Double],
        session: DebugCaptureSession?,
        frameOutputs: [PendingFrameOutput]
    ) {
        let wasCalibrating = calibrationCompletion != nil
        let calibrationResult: CalibrationResult?
        let productState: PostureState
        if let completion = calibrationCompletion {
            calibrationCompletion = nil
            calibrationSummaries.removeAll()
            calibrationAttempts = 0
            let result = CalibrationResult.rejected(.cameraUnavailable)
            calibrationResult = result
            productState = resolveCalibration(result, completion: completion)
        } else {
            calibrationResult = nil
            productState = .blocked
            emitBlocked(reason)
        }
        let diagnostic = PostureDiagnostic(
            assessment: .noEval,
            productState: productState,
            evidence: .noEval,
            summary: summary,
            baselineCenter: settings.baseline?.center,
            reason: reason.rawValue,
            frames: frames,
            stageProcessingMilliseconds: stageTimings
        )
        let afterOutput: @Sendable () -> Void
        if wasCalibrating {
            afterOutput = {}
        } else {
            afterOutput = { self.scheduleFollowingBurstIfNeeded(startedAt: startedAt) }
        }
        deliverDiagnostic(
            diagnostic,
            session: session,
            verdict: nil,
            calibrationResult: calibrationResult,
            baseline: settings.baseline,
            frameOutputs: frameOutputs,
            afterOutput: afterOutput
        )
    }

    private func calibrationDiagnostic(
        result: CalibrationResult?,
        productState: PostureState,
        summary: BurstSummary,
        frames: [TimedFrame],
        stageTimings: [String: Double]
    ) -> PostureDiagnostic {
        let reason: String
        switch result {
        case .none:
            reason = "calibration attempt \(calibrationAttempts)/\(CameraBurstTiming.maximumCalibrationAttempts)"
        case .some(.accepted): reason = "calibration accepted"
        case .some(.rejected(let rejectReason)): reason = "calibration rejected: \(rejectReason.rawValue)"
        }
        let acceptedCenter: Double?
        if case .some(.accepted(let accepted)) = result {
            acceptedCenter = accepted.center
        } else {
            acceptedCenter = settings.baseline?.center
        }
        return PostureDiagnostic(
            assessment: .noEval,
            productState: productState,
            evidence: .noEval,
            summary: summary,
            baselineCenter: acceptedCenter,
            reason: reason,
            frames: frames,
            stageProcessingMilliseconds: stageTimings
        )
    }

    private func baselineForSession(_ result: CalibrationResult) -> Baseline? {
        if case .accepted(let accepted) = result { return accepted }
        return settings.baseline
    }

    private func averageStageTimings(_ frames: [TimedFrame]) -> [String: Double] {
        var totals: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for frame in frames {
            for (stage, milliseconds) in frame.analysis.processingMilliseconds {
                totals[stage, default: 0] += milliseconds
                counts[stage, default: 0] += 1
            }
        }
        return totals.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value / Double(counts[entry.key] ?? 1)
        }
    }

    private func deliverDiagnostic(
        _ diagnostic: PostureDiagnostic,
        session: DebugCaptureSession?,
        verdict: BurstVerdict?,
        calibrationResult: CalibrationResult?,
        baseline: Baseline?,
        frameOutputs: [PendingFrameOutput],
        afterOutput: @Sendable @escaping () -> Void
    ) {
        guard let session else {
            emitDiagnostic(diagnostic)
            afterOutput()
            return
        }
        let store = debugStore
        let runner = localAnalysisRunner
        outputQueue.async {
            var completed = diagnostic
            for frame in frameOutputs {
                store.writeFrame(
                    session: frame.session,
                    index: frame.index,
                    time: frame.time,
                    inputImage: store.inputImage(from: frame.sample.sampleBuffer),
                    depthImage: frame.depthMap.flatMap { self.depthProvider.debugImage(for: $0) },
                    analysis: frame.analysis
                )
            }
            let path = store.writeSession(
                session: session,
                verdict: verdict,
                calibrationResult: calibrationResult,
                diagnostic: diagnostic,
                baseline: baseline
            )
            if !path.isEmpty { completed.debugArtifactPath = path }
            self.emitDiagnostic(completed)
            self.queue.async(execute: afterOutput)
            if runner.isEnabled, !path.isEmpty {
                self.localAnalysisQueue.async { runner.run(commonSessionPath: path) }
            }
        }
    }

    private func scheduleFollowingBurstIfNeeded(startedAt: Date) {
        guard isRunning else { return }
        scheduleNextBurst(after: CameraBurstTiming.remainingCheckDelay(
            configuredSeconds: settings.checkIntervalSeconds,
            startedAt: startedAt
        ))
    }

    private func isBurstCurrent(_ runID: Int) -> Bool {
        queue.sync { burstRunID == runID && burstStartDate != nil }
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
        currentDebugSession = nil
        frames.removeAll()
        pendingFrameOutputs.removeAll()
        immediateCheckPending = false
        isPrewarmingModel = false
        calibrationCompletion = nil
        calibrationSummaries.removeAll()
        calibrationAttempts = 0
    }

    private func resolveVerdict(_ verdict: BurstVerdict) -> PostureState {
        guard let callback = onVerdict else {
            return switch verdict.assessment {
            case .good: .good
            case .bad: .bad
            case .noEval: .noEval
            }
        }
        if Thread.isMainThread {
            return MainActor.assumeIsolated { callback(verdict) }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { callback(verdict) }
        }
    }

    private func emitDiagnostic(_ diagnostic: PostureDiagnostic) {
        let callback = onDiagnostic
        DispatchQueue.main.async { callback?(diagnostic) }
    }

    private func resolveCalibration(
        _ result: CalibrationResult,
        completion: @MainActor @Sendable @escaping (CalibrationResult) -> PostureState
    ) -> PostureState {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { completion(result) }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { completion(result) }
        }
    }

    private func emitBlocked(_ reason: CameraBlockReason) {
        let callback = onBlocked
        DispatchQueue.main.async { callback?(reason) }
    }

    private func emitCaptureActivity(_ active: Bool) {
        let callback = onCaptureActivity
        DispatchQueue.main.async { callback?(active) }
    }

    private func emitNextCheck(_ seconds: Int) {
        let callback = onNextCheckUpdate
        DispatchQueue.main.async { callback?(seconds) }
    }

    @objc private func sessionInterrupted() {
        queue.async {
            self.session?.stopRunning()
            self.emitCaptureActivity(false)
            self.invalidateCurrentBurst()
            if self.isRunning { self.scheduleNextBurst(after: self.settings.checkIntervalSeconds) }
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
            if self.isRunning { self.scheduleNextBurst(after: self.settings.checkIntervalSeconds) }
        }
    }
}

private struct CaptureSnapshot: Sendable {
    let runID: Int
    let startDate: Date
    let timestamp: Double
    let frameIndex: Int
    let debugSession: DebugCaptureSession?
}

private struct SampleBufferBox: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
}

private struct PendingFrameOutput: @unchecked Sendable {
    let session: DebugCaptureSession
    let index: Int
    let time: Double
    let sample: SampleBufferBox
    let depthMap: RelativeDepthMap?
    let analysis: FrameAnalysis
}

private enum CameraError: Error {
    case noCamera
    case cannotAddInput
    case cannotAddOutput
}

/// 점검이 진행될 수 없는 이유. rawValue는 디버그 아티팩트의 reason 문자열로도 쓰인다.
public enum CameraBlockReason: String, Equatable, Sendable {
    case permissionDenied = "camera permission denied"
    case unavailable = "camera unavailable"
}

public enum CameraAuthorizationAction: Equatable {
    case start
    case requestAccess
    case blocked(CameraBlockReason)
}

public enum CameraBurstCompletionAction: Equatable {
    case process
    case blocked(CameraBlockReason)
}
