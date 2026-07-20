import Foundation

public enum CalibrationRejectReason: String, Codable, Equatable, Sendable {
    case noReliableBursts
    case unstableBaseline
}

public enum CalibrationResult: Equatable, Sendable {
    case accepted(Baseline)
    case rejected(CalibrationRejectReason)
}

public struct Calibrator: Sendable {
    public init() {}

    public func capture(
        from summaries: [BurstSummary],
        captureConfiguration: CaptureConfiguration?,
        now: Date = Date()
    ) -> CalibrationResult {
        guard let captureConfiguration else {
            return .rejected(.noReliableBursts)
        }
        let valid = summaries.filter {
            $0.validFrameCount >= Tuning.minimumValidFrames &&
                ($0.featureMAD ?? .infinity) <= Tuning.maximumBurstMAD &&
                $0.medianFeature != nil
        }
        guard valid.count >= Tuning.requiredCalibrationBursts else {
            return .rejected(.noReliableBursts)
        }
        let centers = valid.compactMap(\.medianFeature)
        guard let center = median(centers) else {
            return .rejected(.noReliableBursts)
        }
        let betweenBurstMAD = median(centers.map { abs($0 - center) }) ?? .infinity
        guard betweenBurstMAD <= Tuning.maximumCalibrationMAD else {
            return .rejected(.unstableBaseline)
        }
        let withinBurstMAD = median(valid.compactMap(\.featureMAD)) ?? 0
        return .accepted(Baseline(
            center: center,
            dispersion: max(withinBurstMAD, betweenBurstMAD),
            burstCount: valid.count,
            createdAt: now,
            captureConfiguration: captureConfiguration
        ))
    }

    private func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
