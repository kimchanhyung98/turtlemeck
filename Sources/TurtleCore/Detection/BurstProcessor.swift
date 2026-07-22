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
        let features = frames.compactMap(\.analysis.feature)
        var exclusions: [FrameExclusionReason: Int] = [:]
        for reason in frames.compactMap(\.analysis.exclusionReason) {
            exclusions[reason, default: 0] += 1
        }
        let center = median(features)
        let mad = center.flatMap { center in median(features.map { abs($0 - center) }) }
        let anchors: [(midY: Double, width: Double)] = frames.compactMap { frame in
            guard
                frame.analysis.isValid,
                let left = frame.analysis.landmarks.leftShoulder,
                let right = frame.analysis.landmarks.rightShoulder
            else { return nil }
            return ((left.y + right.y) / 2, hypot(left.x - right.x, left.y - right.y))
        }
        return BurstSummary(
            totalFrameCount: frames.count,
            validFrameCount: features.count,
            medianFeature: center,
            featureMAD: mad,
            exclusionCounts: exclusions,
            medianShoulderMidY: median(anchors.map(\.midY)),
            medianShoulderWidth: median(anchors.map(\.width))
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

        // 머리는 감지됐지만 정상 자세를 확인할 수 없는 프레임(턱 괴기·머리 처짐·어깨 미신뢰 등)이
        // 버스트의 과반이면 판정 불가(noEval)가 아니라 비정상 자세 증거다. 사람이 없는 경우만 noEval로 남긴다.
        // 과반 조건은 사람 부재(noSubject) 프레임이 섞인 버스트가 소수 프레임만으로 비정상이 되는 것을 막는다.
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
        guard let baseline else {
            return BurstVerdict(evidence: .noEval, summary: summary, reason: "baseline required")
        }
        guard let captureConfiguration else {
            return BurstVerdict(evidence: .noEval, summary: summary, reason: "capture configuration unavailable")
        }
        guard baseline.captureConfiguration == captureConfiguration else {
            return BurstVerdict(evidence: .noEval, summary: summary, reason: "capture configuration changed")
        }

        // 카메라·해상도·방향이 같아도 리드 각도나 착석 거리(책상 배치)가 바뀌면 feature 규모가 달라진다.
        // 보정 시점의 어깨 기준 구도에서 크게 벗어난 버스트는 판정하지 않고 재보정을 안내한다.
        if let anchorMidY = baseline.shoulderMidY, let anchorWidth = baseline.shoulderWidth, anchorWidth > 0,
           let burstMidY = summary.medianShoulderMidY, let burstWidth = summary.medianShoulderWidth {
            let framingChanged = abs(burstMidY - anchorMidY) > Tuning.maximumShoulderAnchorShiftY
                || abs(burstWidth - anchorWidth) / anchorWidth > Tuning.maximumShoulderAnchorWidthRatio
            if framingChanged {
                return BurstVerdict(evidence: .noEval, summary: summary, reason: "framing changed")
            }
        }

        let delta = feature - baseline.center
        let worsening = Tuning.worseningMargin(baselineDispersion: baseline.dispersion)
        let recovery = Tuning.recoveryMargin(baselineDispersion: baseline.dispersion)
        if delta >= worsening {
            return BurstVerdict(evidence: .worsened, summary: summary, baselineDelta: delta)
        }
        if delta <= recovery {
            return BurstVerdict(evidence: .normal, summary: summary, baselineDelta: delta)
        }
        return BurstVerdict(evidence: .insufficient, summary: summary, baselineDelta: delta, reason: "inside hysteresis band")
    }

    private func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
