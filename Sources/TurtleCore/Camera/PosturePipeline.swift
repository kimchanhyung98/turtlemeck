import Foundation

public final class PosturePipeline {
    private let analyzer: PostureAnalyzer
    private let classifier: ViewpointClassifier
    private var viewpointStabilizer: ViewpointStabilizer
    private var signalFilters: [SignalKind: OneEuroFilter] = [:]
    private let signalFilterAlpha: Double
    private var activeAlgorithm: PostureAlgorithmID?

    public init(
        analyzer: PostureAnalyzer = PostureAnalyzer(),
        classifier: ViewpointClassifier = ViewpointClassifier(),
        stableViewpointFrames: Int = 3,
        signalFilterAlpha: Double = 0.8
    ) {
        self.analyzer = analyzer
        self.classifier = classifier
        self.viewpointStabilizer = ViewpointStabilizer(requiredFrames: stableViewpointFrames)
        self.signalFilterAlpha = signalFilterAlpha
    }

    public func reset() {
        // 각 버스트는 독립 판정 단위이므로 이전 버스트의 필터/시점 상태를 끌고 오지 않는다.
        resetAnalysisState()
        activeAlgorithm = nil
    }

    public func process(_ landmarks: PoseLandmarks, settings: Settings, baseline: Baseline?, timestamp: Double? = nil) -> AnalyzedFrame {
        if activeAlgorithm != settings.postureAlgorithm {
            resetAnalysisState()
            activeAlgorithm = settings.postureAlgorithm
        }

        let rawViewpoint = classifier.classify(landmarks)
        let stableViewpoint = viewpointStabilizer.stabilize(rawViewpoint)
        let algorithm = PostureAlgorithmFactory.make(settings.postureAlgorithm, analyzer: analyzer)
        let context = PostureAnalysisContext(
            baseline: baseline,
            sensitivity: settings.sensitivity,
            viewpoint: stableViewpoint
        )
        let frame = algorithm.analyze(landmarks, context: context)
        var result = smooth(frame, landmarks: landmarks, baseline: baseline, sensitivity: settings.sensitivity, timestamp: timestamp)
        // 정면 응시 프레임이면 신호 종류와 무관하게 얼굴 위치를 남겨, 보정 시 frontFace baseline을 확보한다(개인화: 카메라 높이/방향).
        if let box = landmarks.faceBoundingBox, abs(landmarks.faceYawDegrees ?? 0) <= Tuning.faceProxyMaxYaw {
            result.faceBottomY = box.y
        }
        return result
    }

    private func resetAnalysisState() {
        signalFilters.removeAll()
        viewpointStabilizer.reset()
    }

    private func smooth(_ frame: AnalyzedFrame, landmarks: PoseLandmarks, baseline: Baseline?, sensitivity: Sensitivity, timestamp: Double?) -> AnalyzedFrame {
        guard var signal = frame.signal else {
            return frame
        }

        // 실제 카메라 경로는 timestamp 기반 1€ 필터를 사용하고, 단위 테스트의 timestamp 없는 경로는 5fps 간격을 가정한다.
        let minCutoff = max(0.001, 1 - signalFilterAlpha)
        var filter = signalFilters[signal.kind] ?? OneEuroFilter(minCutoff: minCutoff, beta: 0.005, dCutoff: 1)
        if let timestamp {
            signal.angleDegrees = filter.filter(signal.angleDegrees, timestamp: timestamp)
        } else {
            signal.angleDegrees = filter.filter(signal.angleDegrees)
        }
        signalFilters[signal.kind] = filter

        var smoothed = frame
        smoothed.signal = signal
        let base = PostureJudge.assess(signal, baseline: baseline, sensitivity: sensitivity)
        // 스무딩 후 재판정에서도 "바른 자세는 양성 증거 필요" 게이트를 동일 적용한다(머리 기울임/삐딱이면 good 제외).
        let gate = AlgorithmSupport.applyUprightGate(base, pose: landmarks)
        smoothed.assessment = gate.assessment
        if let reason = gate.reason {
            smoothed.reason = reason
        }
        return smoothed
    }
}

private struct ViewpointStabilizer {
    private let requiredFrames: Int
    private var stable: ViewpointResult?
    private var candidate: ViewpointResult?
    private var candidateCount = 0

    init(requiredFrames: Int) {
        self.requiredFrames = max(1, requiredFrames)
    }

    mutating func reset() {
        stable = nil
        candidate = nil
        candidateCount = 0
    }

    mutating func stabilize(_ raw: ViewpointResult) -> ViewpointResult {
        guard let current = stable else {
            stable = raw
            return raw
        }

        guard raw.band != current.band else {
            stable = raw
            candidate = nil
            candidateCount = 0
            return raw
        }

        if candidate?.band == raw.band {
            candidateCount += 1
        } else {
            candidate = raw
            candidateCount = 1
        }

        if candidateCount >= requiredFrames {
            stable = raw
            candidate = nil
            candidateCount = 0
            return raw
        }

        return current
    }
}
