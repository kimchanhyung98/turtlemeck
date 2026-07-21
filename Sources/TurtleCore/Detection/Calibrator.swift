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

    /// 보정에 쓸 수 있는 버스트 기준. 수집 루프의 조기 종료 판단도 같은 기준을 사용해야 한다.
    public static func isReliable(_ summary: BurstSummary) -> Bool {
        summary.validFrameCount >= Tuning.minimumValidFrames &&
            (summary.featureMAD ?? .infinity) <= Tuning.maximumBurstMAD &&
            summary.medianFeature != nil
    }

    public func capture(
        from summaries: [BurstSummary],
        captureConfiguration: CaptureConfiguration?,
        now: Date = Date()
    ) -> CalibrationResult {
        guard let captureConfiguration else {
            return .rejected(.noReliableBursts)
        }
        let valid = summaries.filter(Self.isReliable)
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
