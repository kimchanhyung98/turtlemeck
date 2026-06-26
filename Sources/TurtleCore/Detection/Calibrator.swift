import Foundation

public enum CalibrationRejectReason: String, Codable, Equatable, Sendable {
    case noReliableFrames
    case alreadySlouched
}

public enum CalibrationResult: Equatable, Sendable {
    case accepted(Baseline)
    case rejected(CalibrationRejectReason)
}

public struct Calibrator {
    public init() {}

    public func capture(from frames: [AnalyzedFrame], requiredAlgorithm: PostureAlgorithmID? = nil) -> CalibrationResult {
        let signals = frames.compactMap(\.signal).filter { signal in
            return signal.confidence >= Self.calibrationConfidenceThreshold(for: signal.kind)
        }
        guard !signals.isEmpty else {
            return .rejected(.noReliableFrames)
        }

        // 신호 종류별로 분리해 baseline을 만든다.
        let profileAngle = percentile(signals.filter { $0.kind == .profile2D }.map(\.angleDegrees), 0.75)
        let frontRatio = percentile(signals.filter { $0.kind == .front2D }.map { $0.angleDegrees / 90 }, 0.75)
        let threeQuarterAngle = percentile(signals.filter { $0.kind == .threeQuarter2D }.map(\.angleDegrees), 0.75)
        let bodyFrameAngle = percentile(signals.filter { $0.kind == .body3D }.map(\.angleDegrees), 0.75)
        let depthDeltaNorm = percentile(signals.filter { $0.kind == .depth3D }.map(\.angleDegrees), 0.75)
        let relativeDepthDelta = percentile(signals.filter { $0.kind == .relativeDepth }.map(\.angleDegrees), 0.75)
        // 얼굴 위치 보조 baseline — 모든 평가 프레임의 얼굴 위치(body 성공/실패 무관)를 모아 정자세 분포의 하단(0.25 percentile)을
        // 보수 기준으로 잡는다(전방머리=y 하락 판정의 false-positive 억제 + 카메라 높이/방향 개인화).
        // 프레임의 faceBottomY를 우선 쓰되, 없으면 frontFace 신호값으로 폴백한다.
        let frontFaceY = percentile(frames.compactMap { frame -> Double? in
            frame.faceBottomY ?? (frame.signal?.kind == .frontFace ? frame.signal?.angleDegrees : nil)
        }, 0.25)

        // "클수록 좋음" 측면 각이 이미 구부정하면 보정 거부.
        if let profileAngle, profileAngle < Tuning.profileBaselineRejectAngle {
            return .rejected(.alreadySlouched)
        }

        guard profileAngle != nil || frontRatio != nil || threeQuarterAngle != nil || bodyFrameAngle != nil || depthDeltaNorm != nil || relativeDepthDelta != nil || frontFaceY != nil else {
            return .rejected(.noReliableFrames)
        }

        let baseline = Baseline(
            profileAngle: profileAngle,
            frontHeadDropRatio: frontRatio,
            threeQuarterAngle: threeQuarterAngle,
            bodyFrameAngle: bodyFrameAngle,
            depthDeltaNorm: depthDeltaNorm,
            relativeDepthDelta: relativeDepthDelta,
            frontFaceBottomY: frontFaceY
        )

        guard Self.satisfiesRequiredBaseline(baseline, for: requiredAlgorithm) else {
            return .rejected(.noReliableFrames)
        }

        return .accepted(baseline)
    }

    /// 신호 종류별 보정 통과 신뢰도 임계.
    /// 측면/3-4 각은 머리(귀/눈)가 고신뢰여도 반대측 어깨가 웹캠에서 저신뢰(실측 0.2~0.4)라
    /// `min(head, shoulder)` 신호 confidence가 낮게 나온다. 얼굴 보조 신호도 마찬가지다.
    /// 이들은 실시간 판정과 동일한 추적 임계로 보정을 허용하고, percentile(0.75) baseline이 노이즈를 흡수한다.
    /// (측면 배치에서 보정이 항상 실패하던 문제 해결 — 리서치가 핵심으로 본 측면/3-4 보정 활성화.)
    private static func calibrationConfidenceThreshold(for kind: SignalKind) -> Double {
        switch kind {
        case .frontFace, .profile2D, .threeQuarter2D, .relativeDepth:
            return Tuning.minimumTrackingConfidence
        case .front2D, .body3D, .depth3D:
            return Tuning.minimumLandmarkConfidence
        }
    }

    private static func satisfiesRequiredBaseline(_ baseline: Baseline, for algorithm: PostureAlgorithmID?) -> Bool {
        guard let algorithm else {
            return true
        }
        switch algorithm {
        case .mlAuto:
            return baseline.relativeDepthDelta != nil || baseline.depthDeltaNorm != nil || baseline.bodyFrameAngle != nil
        case .coreMLRelativeDepth:
            return baseline.relativeDepthDelta != nil
        case .depthDelta:
            return baseline.depthDeltaNorm != nil
        case .bodyFrame3D:
            return baseline.bodyFrameAngle != nil
        case .profileGeometry:
            return baseline.profileAngle != nil || baseline.threeQuarterAngle != nil
        case .frontProxy:
            return baseline.frontHeadDropRatio != nil || baseline.frontFaceBottomY != nil
        case .fusion:
            return true
        }
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else {
            return nil
        }
        guard sorted.count > 1 else {
            return sorted[0]
        }

        let rank = max(0, min(1, p)) * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Int(rank.rounded(.up))
        let fraction = rank - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}
