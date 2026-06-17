import Foundation

public final class PosturePipeline: @unchecked Sendable {
    private let analyzer: PostureAnalyzer
    private let classifier: ViewpointClassifier
    private var viewpointStabilizer: ViewpointStabilizer
    private var signalFilters: [SignalKind: OneEuroFilter] = [:]
    private let signalFilterAlpha: Double

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
        signalFilters.removeAll()
        viewpointStabilizer.reset()
    }

    public func process(_ landmarks: PoseLandmarks, settings: Settings, baseline: Baseline?, timestamp: Double? = nil) -> AnalyzedFrame {
        let rawViewpoint = classifier.classify(landmarks)
        let stableViewpoint = viewpointStabilizer.stabilize(rawViewpoint)
        let frame = analyzer.analyze(
            landmarks,
            baseline: baseline,
            cameraPlacement: settings.cameraPlacement,
            sensitivity: settings.sensitivity,
            viewpointOverride: stableViewpoint
        )
        return smooth(frame, baseline: baseline, sensitivity: settings.sensitivity, timestamp: timestamp)
    }

    private func smooth(_ frame: AnalyzedFrame, baseline: Baseline?, sensitivity: Sensitivity, timestamp: Double?) -> AnalyzedFrame {
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
        smoothed.assessment = assessment(for: signal, baseline: baseline, sensitivity: sensitivity)
        return smoothed
    }

    private func assessment(for signal: PostureSignal, baseline: Baseline?, sensitivity: Sensitivity) -> PostureAssessment {
        switch signal.kind {
        case .front2D:
            guard let baselineRatio = baseline?.frontHeadDropRatio else {
                return .noEval
            }
            return signal.angleDegrees / 90 < baselineRatio - Tuning.frontRelativeDrop ? .bad : .good
        case .threeQuarter2D:
            return classify(angle: signal.angleDegrees, baselineAngle: baseline?.threeQuarterAngle, sensitivity: sensitivity)
        case .profile2D, .body3D:
            return classify(angle: signal.angleDegrees, baselineAngle: baseline?.profileAngle, sensitivity: sensitivity)
        }
    }

    private func classify(angle: Double, baselineAngle: Double?, sensitivity: Sensitivity) -> PostureAssessment {
        if let baselineAngle {
            return angle < baselineAngle - Tuning.profileRelativeDrop ? .bad : .good
        }
        return angle < Tuning.absoluteBadAngle(for: sensitivity) ? .bad : .good
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
