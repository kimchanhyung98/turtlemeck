import Foundation

public struct TimedFrame: Codable, Equatable, Sendable {
    public var time: Double
    public var analysis: FrameAnalysis
    public var index: Int

    public init(time: Double, analysis: FrameAnalysis, index: Int) {
        self.time = time
        self.analysis = analysis
        self.index = index
    }
}

public struct BurstProcessor: Sendable {
    public init() {}

    public func summarize(_ frames: [TimedFrame]) -> BurstSummary {
        let features = frames.compactMap { frame in
            frame.analysis.isValid ? frame.analysis.feature : nil
        }
        var exclusions: [FrameExclusionReason: Int] = [:]
        for reason in frames.compactMap(\.analysis.exclusionReason) {
            exclusions[reason, default: 0] += 1
        }
        let center = Statistics.median(features)
        let mad = center.flatMap { center in Statistics.median(features.map { abs($0 - center) }) }
        let anchors: [(midY: Double, width: Double)] = frames.compactMap { frame in
            guard
                frame.analysis.isValid,
                let geometry = frame.analysis.landmarks.upperBodyGeometry
            else { return nil }
            return (geometry.shoulderY, geometry.shoulderWidth)
        }
        return BurstSummary(
            totalFrameCount: frames.count,
            validFrameCount: features.count,
            medianFeature: center,
            featureMAD: mad,
            exclusionCounts: exclusions,
            medianShoulderMidY: Statistics.median(anchors.map(\.midY)),
            medianShoulderWidth: Statistics.median(anchors.map(\.width))
        )
    }

    public func process(
        _ frames: [TimedFrame],
        baseline: Baseline?,
        captureConfiguration: CaptureConfiguration?
    ) -> BurstVerdict {
        let summary = summarize(frames)
        guard summary.totalFrameCount >= Tuning.minimumValidFrames else {
            return BurstVerdict(evidence: .noEval, summary: summary, reason: "insufficient captured frames")
        }

        let validatedBaseline: Baseline?
        if let baseline {
            guard
                baseline.center.isFinite,
                baseline.dispersion.isFinite,
                (0...Tuning.maximumBurstMAD).contains(baseline.dispersion),
                baseline.burstCount >= Tuning.requiredCalibrationBursts,
                baseline.featureVersion == Baseline.currentFeatureVersion
            else {
                return BurstVerdict(evidence: .noEval, summary: summary, reason: "baseline invalid")
            }
            guard let captureConfiguration else {
                return BurstVerdict(evidence: .noEval, summary: summary, reason: "capture configuration unavailable")
            }
            guard baseline.captureConfiguration == captureConfiguration else {
                return BurstVerdict(evidence: .noEval, summary: summary, reason: "capture configuration changed")
            }
            validatedBaseline = baseline
        } else {
            validatedBaseline = nil
        }

        // 머리는 보이지만 자세를 평가할 수 없는 프레임이 과반이면 악화 증거로 본다.
        // 사람 부재나 기술 실패는 판정 불가로 남긴다.
        // 사람 부재가 많은 버스트에서 소수 프레임만으로 악화 판정이 나지 않도록 과반을 요구한다.
        let unassessableCount = frames.filter { frame in
            guard let reason = frame.analysis.exclusionReason else { return false }
            return reason.isSubjectUnassessable && !frame.analysis.landmarks.reliableHeadAnchors.isEmpty
        }.count
        if unassessableCount >= Tuning.minimumValidFrames, unassessableCount * 2 > summary.totalFrameCount {
            return BurstVerdict(evidence: .worsened, summary: summary, reason: "posture unassessable")
        }

        let validRatio = Double(summary.validFrameCount) / Double(summary.totalFrameCount)
        guard
            summary.validFrameCount >= Tuning.minimumValidFrames,
            validRatio >= Tuning.minimumValidFrameRatio,
            let feature = summary.medianFeature,
            let mad = summary.featureMAD
        else {
            return BurstVerdict(evidence: .noEval, summary: summary, reason: "insufficient valid frames")
        }
        guard mad <= Tuning.maximumBurstMAD else {
            return BurstVerdict(evidence: .noEval, summary: summary, reason: "unstable burst")
        }
        guard let baseline = validatedBaseline else {
            return BurstVerdict(evidence: .noEval, summary: summary, reason: "baseline required")
        }

        // 카메라 설정이 같아도 화면 각도나 착석 거리가 바뀌면 특성값 규모가 달라진다.
        // 어깨 구도가 보정 시점과 크게 다르면 판정하지 않고 재보정을 안내한다.
        if let anchorMidY = baseline.shoulderMidY, let anchorWidth = baseline.shoulderWidth, anchorWidth > 0,
           let burstMidY = summary.medianShoulderMidY, let burstWidth = summary.medianShoulderWidth {
            let framingChanged = abs(burstMidY - anchorMidY) > Tuning.maximumShoulderAnchorShiftY
                || abs(burstWidth - anchorWidth) / anchorWidth > Tuning.maximumShoulderAnchorWidthRatio
            if framingChanged {
                return BurstVerdict(evidence: .noEval, summary: summary, reason: "framing changed")
            }
        }

        let delta = feature - baseline.center
        let distanceFromBaseline = abs(delta)
        let worsening = Tuning.worseningMargin(baselineDispersion: baseline.dispersion)
        let recovery = Tuning.recoveryMargin(baselineDispersion: baseline.dispersion)
        if distanceFromBaseline >= worsening {
            return BurstVerdict(evidence: .worsened, summary: summary, baselineDelta: delta)
        }
        if distanceFromBaseline <= recovery {
            return BurstVerdict(evidence: .normal, summary: summary, baselineDelta: delta)
        }
        return BurstVerdict(evidence: .insufficient, summary: summary, baselineDelta: delta, reason: "inside hysteresis band")
    }
}
