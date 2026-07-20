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
        return BurstSummary(
            totalFrameCount: frames.count,
            validFrameCount: features.count,
            medianFeature: center,
            featureMAD: mad,
            exclusionCounts: exclusions
        )
    }

    public func process(
        _ frames: [TimedFrame],
        baseline: Baseline?,
        captureConfiguration: CaptureConfiguration?,
        sensitivity: Sensitivity
    ) -> BurstVerdict {
        let summary = summarize(frames)
        guard summary.totalFrameCount >= Tuning.minimumValidFrames else {
            return BurstVerdict(evidence: .noEval, summary: summary, reason: "insufficient captured frames")
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

        let delta = feature - baseline.center
        let worsening = Tuning.worseningMargin(for: sensitivity, baselineDispersion: baseline.dispersion)
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
